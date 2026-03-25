import Foundation
import SQLite3
import AppKit

let APPLE_EPOCH: Double = 978307200
let DB_PATH = NSHomeDirectory() + "/Library/Messages/chat.db"

struct Message: Codable {
    let time: String
    let type: String
    let sender: String
    let receiver: String
    let content: String
}

func parseAppleDate(_ raw: Int64) -> String {
    guard raw > 0 else { return "unknown" }
    let unix = Double(raw) / 1_000_000_000.0 + APPLE_EPOCH
    let date = Date(timeIntervalSince1970: unix)
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return fmt.string(from: date)
}

func printUsage() {
    let usage = """
    Usage: imessage-db-reader [OPTIONS]
      --minutes N       How far back to look (default: 30)
      --type TYPE       sms | imessage | rcs | all (default: all)
      --sender PAT      Regex filter on sender
      --receiver PAT    Regex filter on receiver
      --content PAT     Regex filter on message content
      --limit N         Max results (default: 50)
      --include-sent    Include sent messages
      --help            Show this help
    Output: JSON array to stdout.
    """
    FileHandle.standardError.write(Data(usage.utf8))
}

func matches(_ text: String, pattern: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return text.localizedCaseInsensitiveContains(pattern)
    }
    let range = NSRange(text.startIndex..., in: text)
    return regex.firstMatch(in: text, range: range) != nil
}

func extractTextFromAttributedBody(_ blob: Data) -> String? {
    // Method 1: typedstream format (starts with 0x04 0x0b) — most common in chat.db
    if blob.count > 2 && blob[0] == 0x04 && blob[1] == 0x0b {
        // Use NSUnarchiver (legacy API for typedstream)
        if let obj = NSUnarchiver.unarchiveObject(with: blob) as? NSAttributedString {
            let s = obj.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
    }

    // Method 2: bplist (NSKeyedArchiver) format
    if blob.count > 6 && blob.prefix(6).elementsEqual([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]) {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: blob)
            unarchiver.requiresSecureCoding = false
            if let attrStr = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString {
                unarchiver.finishDecoding()
                let s = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }
            unarchiver.finishDecoding()
        } catch {}
    }

    // Method 3: brute-force scan for the longest printable UTF-8 subsequence
    var best = ""
    var current = ""
    for byte in blob {
        if byte >= 0x20 && byte < 0x7F {
            current.append(Character(UnicodeScalar(byte)))
        } else if byte >= 0xC0 {
            // potential start of multi-byte UTF-8 char — try to include it
            if let scalar = UnicodeScalar(UInt32(byte)) {
                current.append(Character(scalar))
            }
        } else {
            if current.count > best.count { best = current }
            current = ""
        }
    }
    if current.count > best.count { best = current }
    let trimmed = best.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.count >= 2 ? trimmed : nil
}

func main() -> Int32 {
    var minutes = 30
    var serviceFilter: String? = nil
    var senderPattern: String? = nil
    var receiverPattern: String? = nil
    var contentPattern: String? = nil
    var limit = 50
    var includeSent = false

    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--minutes":
            i += 1; minutes = Int(args[i]) ?? 30
        case "--type":
            i += 1
            let t = args[i].lowercased()
            if t != "all" {
                let map = ["sms": "SMS", "imessage": "iMessage", "rcs": "RCS"]
                serviceFilter = map[t]
            }
        case "--sender":
            i += 1; senderPattern = args[i]
        case "--receiver":
            i += 1; receiverPattern = args[i]
        case "--content":
            i += 1; contentPattern = args[i]
        case "--limit":
            i += 1; limit = Int(args[i]) ?? 50
        case "--include-sent":
            includeSent = true
        case "--help", "-h":
            printUsage(); return 0
        default:
            break
        }
        i += 1
    }

    // Copy db + WAL to temp dir so SQLite can do WAL recovery without lock conflicts
    let tmpDir = NSTemporaryDirectory() + "imsg-\(ProcessInfo.processInfo.globallyUniqueString)"
    let fm = FileManager.default
    do {
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        try Data(contentsOf: URL(fileURLWithPath: DB_PATH))
            .write(to: URL(fileURLWithPath: tmpDir + "/chat.db"))
        let walPath = DB_PATH + "-wal"
        if fm.fileExists(atPath: walPath) {
            try Data(contentsOf: URL(fileURLWithPath: walPath))
                .write(to: URL(fileURLWithPath: tmpDir + "/chat.db-wal"))
        }
    } catch {
        let msg = error.localizedDescription
        if msg.contains("permission") || msg.contains("Operation not permitted") {
            FileHandle.standardError.write(Data(
                "ERROR: Full Disk Access required for this binary.\n".utf8
            ))
        } else {
            FileHandle.standardError.write(Data("ERROR: copy failed: \(msg)\n".utf8))
        }
        try? fm.removeItem(atPath: tmpDir)
        return 1
    }
    defer { try? fm.removeItem(atPath: tmpDir) }

    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE
    let rc = sqlite3_open_v2(tmpDir + "/chat.db", &db, flags, nil)
    guard rc == SQLITE_OK, let db = db else {
        let err = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        FileHandle.standardError.write(Data("ERROR: \(err)\n".utf8))
        return 1
    }
    defer { sqlite3_close(db) }

    sqlite3_busy_timeout(db, 3000)

    let cutoffUnix = Date().timeIntervalSince1970 - Double(minutes * 60)
    let cutoffApple = Int64((cutoffUnix - APPLE_EPOCH) * 1_000_000_000)

    var sql = """
        SELECT
            m.text, m.date, m.is_from_me, m.service, m.account,
            m.destination_caller_id,
            h.id AS sender_id,
            c.account_id AS chat_account_id,
            m.attributedBody
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE m.date > \(cutoffApple)
          AND (m.text IS NOT NULL AND m.text != '' OR m.attributedBody IS NOT NULL)
    """

    if !includeSent {
        sql += " AND m.is_from_me = 0"
    }
    if let svc = serviceFilter {
        sql += " AND m.service = '\(svc)'"
    }
    sql += " ORDER BY m.date DESC LIMIT \(limit * 3)"

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        let err = String(cString: sqlite3_errmsg(db))
        FileHandle.standardError.write(Data("SQL ERROR: \(err)\n".utf8))
        return 1
    }
    defer { sqlite3_finalize(stmt) }

    var results: [Message] = []

    while sqlite3_step(stmt) == SQLITE_ROW && results.count < limit {
        var text = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        let dateRaw = sqlite3_column_int64(stmt, 1)
        let service = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "unknown"
        let account = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
        let destCaller = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
        let senderID = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        let chatAccount = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""

        // If text column is empty, extract from attributedBody blob
        if text.isEmpty {
            if let blobPtr = sqlite3_column_blob(stmt, 8) {
                let blobLen = sqlite3_column_bytes(stmt, 8)
                let data = Data(bytes: blobPtr, count: Int(blobLen))
                text = extractTextFromAttributedBody(data) ?? ""
            }
        }

        guard !text.isEmpty else { continue }

        var receiver = destCaller.isEmpty ? (account.isEmpty ? chatAccount : account) : destCaller
        if receiver.hasPrefix("p:") || receiver.hasPrefix("e:") {
            receiver = String(receiver.dropFirst(2))
        }

        if let pat = senderPattern, !matches(senderID, pattern: pat) { continue }
        if let pat = receiverPattern, !matches(receiver, pattern: pat) { continue }
        if let pat = contentPattern, !matches(text, pattern: pat) { continue }

        results.append(Message(
            time: parseAppleDate(dateRaw),
            type: service,
            sender: senderID,
            receiver: receiver,
            content: text
        ))
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    if let data = try? encoder.encode(results), let json = String(data: data, encoding: .utf8) {
        print(json)
    }

    return 0
}

exit(main())
