---
name: imessage-reader
description: Read recent iMessage/SMS/RCS messages from the local macOS Messages database.
---

# imessage-reader

读取本机 macOS Messages 数据库中的近期短信/iMessage/RCS 消息。

## 触发场景

用户用自然语言要求查看短信或消息时使用，常见表述：

- "收短信" / "看短信" / "查短信" / "有没有新短信"
- "收 iMessage" / "看消息" / "查消息" / "接收消息"
- "验证码是多少" / "XXX 的验证码" / "刚收到的验证码"
- "查一下 XX 发来的消息"
- "最近 1 小时的短信"
- "发给 138xxxx 的短信"

## 命令

必须通过 Python 包装脚本调用，禁止直接执行 `imessage-db-reader` 二进制。Python 脚本内部会通过 launchctl 以正确的权限上下文执行二进制，直接调用二进制会因 macOS TCC responsible process 机制报权限错误。

```bash
python3 ~/.openclaw/workspace/scripts/imessage_reader.py [OPTIONS]
```

### 参数

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `--minutes N` | 往回查多少分钟 | 30 | `--minutes 60` |
| `--type TYPE` | 消息类型：`sms` / `imessage` / `rcs` / `all` | all | `--type sms` |
| `--sender PATTERN` | 按发送方号码/地址过滤（正则） | 无 | `--sender "95588"` |
| `--receiver PATTERN` | 按接收方号码/地址过滤（正则） | 无 | `--receiver "138"` |
| `--content PATTERN` | 按消息内容过滤（正则） | 无 | `--content "验证码"` |
| `--limit N` | 最多返回条数 | 50 | `--limit 10` |
| `--include-sent` | 同时包含自己发出的消息 | 否 | `--include-sent` |
| `--format FMT` | 输出格式：`text` / `json` | text | `--format json` |

## 参数映射指南

根据用户自然语言自动组合参数：

| 用户说 | 映射 |
|--------|------|
| "收短信" / "看短信" | `--type sms` |
| "收 iMessage" | `--type imessage` |
| "收消息" / "看消息" | （不加 --type，返回全部类型） |
| "最近 1 小时的短信" | `--type sms --minutes 60` |
| "ChatGPT 的验证码" | 见下方「含正则交替的示例」 |
| "验证码是多少" | 见下方「含正则交替的示例」 |
| "95588 发来的短信" | `--type sms --sender "95588"` |
| "发给 138xxxx 的消息" | `--receiver "138xxxx"` |
| "最近 10 条消息" | `--limit 10` |
| "今天所有短信" | `--type sms --minutes 1440` |

**含正则交替的示例**（正则中的 `|` 表示"或"，在 shell 双引号内需原样传入）：

```bash
# "ChatGPT 的验证码"
python3 ~/.openclaw/workspace/scripts/imessage_reader.py --type sms --content "(?i)chatgpt|openai"

# "验证码是多少"（模糊匹配各类验证码关键词和 4-6 位纯数字）
python3 ~/.openclaw/workspace/scripts/imessage_reader.py --content "验证码|验证碼|code|Code|\\b\\d{4,6}\\b"
```

## 输出示例

```
共 2 条消息：

[1] 2026-03-24 23:15:02  SMS
    发送方: 10690955998
    接收方: +8613812345678
    内容: 【OpenAI】Your verification code is 847291. Don't share this code with anyone.

[2] 2026-03-24 23:08:33  SMS
    发送方: 95588
    接收方: +8613812345678
    内容: 您尾号1234的储蓄卡，3月24日消费100.00元。
```

## 安全架构

采用权限隔离设计，Python 脚本本身不接触 chat.db：

```
用户请求 → OpenClaw (node, 无 FDA)
         → imessage_reader.py (python, 无 FDA)
         → imessage-db-reader (compiled Swift binary, 有 FDA, 只读 chat.db)
         → JSON 输出 → Python 格式化 → 返回用户
```

- 只有 `imessage-db-reader` 这一个编译后的二进制拥有完全磁盘访问权限
- 该二进制无依赖、不联网、不写磁盘，源码可审计
- node / python / Terminal 均无需 FDA

## 输出规则

**必须原样转发脚本输出的所有字段，禁止省略任何字段。** 每条消息必须包含以下全部五项：
1. 时间
2. 类型（SMS/iMessage/RCS）
3. 发送方
4. 接收方
5. 内容

如果需要美化格式可以调整排版，但不允许删减字段。

## 注意事项

- 默认只返回收到的消息（不含自己发出的），加 `--include-sent` 可包含
- 内容过滤使用正则，大小写不敏感
- 当用户意图不明确时，默认用 `--type sms --content "验证码|验证碼|code|Code|\\b\\d{4,6}\\b"` 来匹配验证码类消息

## 排障规则

遇到错误时，严格按以下规则执行：

1. 涉及数据库查询的排障都必须通过 Python 包装脚本进行，禁止直接执行 `imessage-db-reader` 二进制来查询消息。直接执行数据库查询会因 TCC responsible process 机制报 FDA 错误，这不是真实的权限问题，不能作为诊断依据。不触库的操作（如 `--help`）可以直接运行
2. 禁止重新编译 `imessage-db-reader`。macOS 的 FDA 授权绑定二进制文件 hash，重新编译会导致 FDA 失效，用户必须重新手动授权
3. 如果 Python 包装脚本报 `Full Disk Access required`，才说明 FDA 确实没配好，引导用户在系统设置中添加：`~/.openclaw/workspace/scripts/imessage-db-reader`
4. 如果 Python 包装脚本报 `database is locked`，属于 SQLite 并发访问的暂时性错误，重试即可，不要误判为 FDA 问题
5. 如果 Python 包装脚本报 `failed to parse reader output`，属于运行时错误（如并发 launchctl job 残留），重试即可，不要误判为 FDA 问题
