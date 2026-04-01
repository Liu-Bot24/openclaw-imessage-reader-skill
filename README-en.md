<div align="center">

# iMessage Reader for OpenClaw

Languages: [简体中文](README.md) · [English](README-en.md)

</div>

An [OpenClaw](https://github.com/openclaw/openclaw) skill that allows you to query iMessage / SMS / RCS messages on your Mac using natural language through any chat tool like Feishu, WeChat, etc., from any device.

## What problem does this solve?

While your Mac can sync iPhone text messages, you might not always be sitting in front of it. Your primary work device might be Windows or Linux, your phone might be charging in another room, or you might be in a meeting where it's inconvenient to check your phone.

This skill turns your always-on Mac into an SMS gateway: as long as your Mac can receive the text message, you can check it through **any chat tool on any device**.

More importantly, it doesn't just "forward messages". You can use natural language to filter them precisely:

- **Filter by Sender** — "Messages from 95588", only view those from ICBC.
- **Filter by Receiver** — "Messages sent to 138xxxx", messages from multiple SIM cards won't interfere.
- **Filter by Content** — "ChatGPT verification code", easily find the exact one among dozens of texts.
- **Filter by Time** — "Messages in the last 1 hour", "All messages today".
- **Filter by Type** — Only view SMS, only iMessage, or all.

No need to take out your phone, no need to unlock it, no need to dig through dozens of spam messages.

**Typical Scenarios:**

- Working on a Windows PC, needing a phone verification code to log into a website → Just say "verification code" to OpenClaw in Feishu, and the code appears in the chat seconds later.
- Phone charging in another room → No need to get up, just send a message to check.
- Phone is on silent in your bag during a meeting → Send a message to check recent texts.
- You have multiple SIM cards, verification codes are scattered across different numbers → Your Mac syncs messages from all numbers; filtering by receiver number gets you the result in one step.

### Demo

Send "receive SMS" in Feishu to get a summary of all texts from the past 24 hours:

<img src="images/demo-overview.jpeg" width="400" />

Supports multi-channel, multi-dimensional filtering—by sender, by receiver, by time range:

<div><img src="images/demo-wechat-sender-filter.jpeg" width="280" /></div>
<div><img src="images/demo-feishu-receiver-filter.jpeg" width="280" /></div>
<div><img src="images/demo-feishu-time-range.jpeg" width="280" /></div>

> Top: WeChat channel, filtering by sender (Sony) and generating a summary / Middle: Feishu channel, filtering by receiver number (starting with 183) / Bottom: Feishu channel, querying complete info within a specific time range

## Security Warning

**This skill will read the text messages on your Mac, including sensitive information like verification codes and bank notifications.** Please be aware of the following risks before use:

- Anyone who can send messages to your OpenClaw might trigger message reading (depending on your OpenClaw channel and approval configurations).
- Message content will be processed by OpenClaw's LLM and returned. Please ensure you trust the model provider you are using.
- It is recommended to use OpenClaw's `exec` approval feature to manually confirm sensitive operations.

Please evaluate whether it is suitable for deployment based on your own security needs.

## Prerequisites

**This skill must be deployed on macOS.** OpenClaw needs to run on an always-on Mac (e.g., Mac Mini, iMac) which is also the device receiving iPhone text messages. You interact with OpenClaw via channels like Feishu or WeChat on other devices (Windows PC, mobile phones, etc.) to query messages.

## Requirement: Ensure Mac Receives iPhone Messages

This skill reads existing messages in the local Messages database on Mac. You must first ensure your iPhone messages sync to your Mac—as long as a message is visible in the Mac's "Messages" app, this skill can read it.

### Apple's Message Sync Mechanism

| Message Type | Sync Method | Requirement |
|---------|---------|------|
| **iMessage** | Can send/receive across devices when signed into the same Apple Account and iMessage is enabled. | Whether full history syncs depends on "Messages in iCloud". |
| **SMS / MMS / RCS** | Requires extra setup for "Messages in iCloud" or "Text Message Forwarding". | See setup steps below. |

**Network Requirements:** Usually, iPhone and Mac don't need to be on the same Wi-Fi constantly. But both must be signed into the same Apple Account with iMessage enabled; during initial setup or troubleshooting, Apple may require devices to have Wi-Fi on and be near each other.

### Method 1: Messages in iCloud (Recommended)

When enabled, all messages (iMessage + SMS + MMS + RCS) sync across devices, including full history. It consumes iCloud storage. Once enabled, no separate "Text Message Forwarding" setup is needed as it's included.

**iPhone:** Settings → Your Name (top) → iCloud → Messages → Turn on "Use on this iPhone".

**Mac:** Messages app → Messages → Settings → iMessage → Check "Enable Messages in iCloud".

### Method 2: Text Message Forwarding

Only forwards newly received SMS/MMS/RCS to Mac. It doesn't sync history and doesn't use iCloud space.

**iPhone:** Settings → Apps → Messages → Text Message Forwarding → Turn on for your Mac.

If you don't see the "Text Message Forwarding" option, first ensure both iPhone and Mac are signed into the same Apple Account, and iMessage is enabled on both.

### Verify Sync is Working

Have someone send you a text (or send one to yourself from another phone) and check if the "Messages" app on your Mac receives it. If it does, you can proceed with installation.

> For detailed instructions, see Apple's official documentation: [Forward text messages from your iPhone to other devices](https://support.apple.com/en-us/HT208386)

## Installation

### System Requirements

- macOS (Verified on macOS Sequoia 15 and macOS Tahoe 26)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3 (built into macOS)
- [OpenClaw](https://github.com/openclaw/openclaw) installed and running normally.

### Quick Install (Let OpenClaw do it)

1. Clone this repository:

```bash
git clone https://github.com/Liu-Bot24/openclaw-imessage-reader-skill.git ~/Desktop/openclaw-imessage-reader-skill
```

2. Send the content of `安装指南.md` to OpenClaw and let it follow the steps. It will automatically handle compilation, file copying, and verification.

3. You only need to do one manual step: **Grant FDA (Full Disk Access) permissions** (OpenClaw will prompt you at the right time).

### Manual Installation

If you aren't using OpenClaw or prefer manual setup, follow the steps in `安装指南.md`. Core workflow:

```bash
# 1. Clone
git clone https://github.com/Liu-Bot24/openclaw-imessage-reader-skill.git
cd openclaw-imessage-reader-skill

# 2. Compile
swiftc -O -o imessage-db-reader imessage-db-reader.swift
codesign -s - -f imessage-db-reader

# 3. Deploy to OpenClaw
mkdir -p ~/.openclaw/workspace/scripts
mkdir -p ~/.openclaw/workspace/skills/imessage-reader
cp imessage-db-reader imessage-db-reader.swift imessage_reader.py ~/.openclaw/workspace/scripts/
cp SKILL.md ~/.openclaw/workspace/skills/imessage-reader/
chmod 755 ~/.openclaw/workspace/scripts/imessage-db-reader
chmod 755 ~/.openclaw/workspace/scripts/imessage_reader.py

# 4. Grant FDA (Manual)
# System Settings → Privacy & Security → Full Disk Access → Add:
# ~/.openclaw/workspace/scripts/imessage-db-reader
```

## Usage

After installation, simply send natural language messages through any channel connected to OpenClaw (Feishu, WeChat, etc.). OpenClaw's LLM will understand your intent and automatically compose query parameters.

### Common Commands

| You Say | Result |
|---------|------|
| Receive SMS | All SMS from the last 30 minutes |
| Receive messages | All messages (including iMessage) from the last 30 minutes |
| What's the verification code | Messages containing keywords like "verification code" from the last 30 minutes |
| ChatGPT code | Messages containing ChatGPT / OpenAI keywords |
| Texts from 95588 | Messages from ICBC |
| Messages sent to 138xxxx | Messages sent to a specific number |
| Messages in the last hour | SMS from the last 60 minutes |
| All messages today | All messages from the last 24 hours |
| Last 10 messages | Limit the number of returned messages |

### Query Parameters

| Parameter | Default | Description |
|------|--------|------|
| Time Range | Last 30 minutes | Can specify any number of minutes, no upper limit; can query all history in the database. |
| Message Type | All | Can be restricted to SMS, iMessage, or RCS. |
| Sender | Any | Supports regex matching for sender number or address. |
| Receiver | Any | Supports regex matching for receiver number, great for multi-SIM users. |
| Content Keywords | Any | Supports regex matching for message content. |
| Return Count | Max 50 | Adjustable. |

### Returned Content

Each message contains five fields:

```
[1] 2026-03-25 10:41:56  SMS
    Sender: +861069095599
    Receiver: +8613800001234
    Content: [ABC] Your verification code is 847291, valid for 5 minutes.
```

## Security Architecture

```
User Request → OpenClaw (node, no FDA)
             → imessage_reader.py (python, no FDA, doesn't touch chat.db)
             → launchctl submit
             → imessage-db-reader (Swift binary, has FDA)
                  ↓
             Copy chat.db + WAL to /tmp → Query on copy → Return JSON → Delete copy
             → Python formats → Return to user
```

### Why only grant FDA to a single binary?

macOS's "Full Disk Access" (FDA) is a heavy permission—processes possessing it can read all protected user data, including Mail, Messages, Safari history, etc.

If FDA is granted to Terminal, Node, or Python, then **all scripts and commands** executed by those processes will have the same permission, creating a massive attack surface.

This skill's approach is to only authorize a single-purpose compiled binary (`imessage-db-reader`). This binary:

- Has no external dependencies, no network access, no disk writing capabilities.
- Does only one thing: reads the Messages database and outputs JSON.
- Its source code is published with the project, available for auditing at any time.

OpenClaw's Node process, Python scripts, and Terminal do not need and should not have FDA.

### Other Design Principles

- **Read-only operation**: Does not write to the original database; queries are performed on a temporary copy, which is deleted immediately after.
- **Process Isolation**: Using `launchctl submit` makes `launchd` the responsible process for TCC, avoiding the need for Node / Python / Terminal to have FDA.

## Technical Details

### macOS TCC and the Responsible Process

macOS's TCC (Transparency, Consent, and Control) mechanism protects `~/Library/Messages/chat.db`. TCC checks not only the process directly accessing the file but also traces up the launch chain to the "responsible process". Running it directly from the terminal makes `Terminal.app` the responsible process, which lacks FDA and will thus be denied. Running it via `launchctl submit` makes `launchd` (PID 1) the responsible process, bypassing this restriction.

### Why copy the database?

`Messages.app` holds a write lock on `chat.db`. Opening it directly as read-only might result in `database is locked`. Copying it to a temporary directory and opening it in read-write mode prompts SQLite to perform WAL recovery automatically, merging new data from WAL logs and avoiding lock conflicts.

### attributedBody

In newer macOS versions, message text is no longer stored in the `message.text` column but in `message.attributedBody`—a typedstream binary blob (the archived form of `NSAttributedString`). This tool uses `NSUnarchiver` to parse the typedstream and extract the plain text.

## File Description

| File | Description |
|------|------|
| `imessage-db-reader.swift` | Swift source code, core reading logic. |
| `imessage_reader.py` | Python wrapper script, handles launchctl calls and output formatting. |
| `SKILL.md` | OpenClaw skill definition, guiding the LLM on when/how to call this skill. |
| `安装指南.md` | Installation steps document for AI assistants (can also be referenced manually). |

## Troubleshooting

| Issue | Solution |
|------|------|
| `Full Disk Access required` | Add FDA to `imessage-db-reader` in System Settings. |
| Permission error when running in terminal directly | Normal behavior. Call it via the Python script or OpenClaw instead. |
| Empty output | Increase `--minutes` value; verify messages are visible in the Mac's "Messages" app. |
| `database is locked` | Temporary issue, just retry. |
| OpenClaw doesn't execute | Check skill loading, exec approvals, and channel tool policies (see section 7.4 in installation guide). |

## Not in UTC+8?

Modify the timezone setting in `imessage-db-reader.swift`:

```swift
fmt.timeZone = TimeZone(identifier: "America/New_York") // Change to your timezone
```

Then recompile, sign, and grant FDA again.

## License

MIT
