# Hook Logic

ระบบ hook ทำงานผ่าน Claude Code event 2 ตัว คือ **UserPromptSubmit** และ **Stop**

## ภาพรวม Flow

```
User พิมพ์ prompt
       │
       ▼
[UserPromptSubmit] ─── log_prompt.ps1 ──► logs/prompts.jsonl
                                       ──► POST /api/prompt → Cloudflare Worker
       │
  Claude ตอบ
       │
       ▼
[Stop] ──────────────── log_usage.ps1 ──► logs/usage.jsonl
                                       ──► logs/combined.jsonl
                                       ──► logs/summary.log
                                       ──► POST /api/usage → Cloudflare Worker
```

---

## Hook 1: `log_prompt.ps1` — UserPromptSubmit

บันทึก prompt ที่ user พิมพ์ทันทีก่อน Claude ตอบ

1. **รับ payload จาก stdin** — Claude ส่ง JSON มาให้ทาง stdin มีฟิลด์ `prompt`, `session_id`, `cwd`
2. **นับ token แบบประมาณ** — ใช้สูตร `length / 3.5` (ไม่ต้องเรียก API)
3. **เขียน log** — append บรรทัด JSON ลงใน `logs/prompts.jsonl`
4. **ส่งไป Worker** — POST ข้อมูลเดียวกันไปที่ `/api/prompt` บน Cloudflare

---

## Hook 2: `log_usage.ps1` — Stop (Claude หยุดตอบ)

บันทึก token usage จริงจาก API response

1. **รับ payload** — มี `session_id` และ `transcript_path` (path ไฟล์ .jsonl ของ conversation)
2. **อ่าน transcript** — ไล่อ่านบรรทัดจากท้ายไฟล์ หา `assistant` message ล่าสุดที่มี `usage`
3. **ดึง token counts** — `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`
4. **เขียน 3 ไฟล์:**
   - `logs/usage.jsonl` — token usage อย่างเดียว
   - `logs/combined.jsonl` — รวม prompt + token usage ในบรรทัดเดียว (ดึง prompt จาก `prompts.jsonl` ตาม `session_id`)
   - `logs/summary.log` — human-readable 1 บรรทัดต่อ turn
5. **ส่งไป Worker** — POST ไปที่ `/api/usage`

---

## Library: `lib/common.ps1`

| Function | หน้าที่ |
|---|---|
| `Write-LogEntry` | เปิดไฟล์แบบ append + thread-safe (`FileShare.ReadWrite`) เขียน JSON 1 บรรทัด |
| `Get-ApproxTokens` | ประมาณ token = `ceil(length / 3.5)` |
| `Send-LogToWorker` | POST JSON ไป Cloudflare Worker โดยใช้ URL + API key จาก `worker/config.ps1` |
| `Invoke-LogRotation` | ถ้าไฟล์ใหญ่เกิน 10MB จะ rename ไฟล์เก่าใส่ timestamp แล้วเริ่มไฟล์ใหม่ |

---

## ข้อสังเกต

- `log_prompt` รู้ token แบบประมาณ (นับตัวอักษร) แต่ `log_usage` รู้ token จริง (จาก API) จึงต้องใช้ทั้ง 2 hook
- `combined.jsonl` join ข้อมูลจากทั้ง 2 hook โดยใช้ `session_id` เป็น key
- `$ErrorActionPreference = "SilentlyContinue"` + `catch {}` ทำให้ hook ไม่เคย crash Claude แม้ log ล้มเหลว
