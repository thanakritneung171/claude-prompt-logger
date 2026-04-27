# claude-prompt-logger

บันทึก prompt ทุกครั้งที่ส่งใน Claude Code พร้อมจำนวน token และ usage ลงไฟล์ JSONL ผ่านระบบ hooks

---

## วิธีติดตั้ง

### ความต้องการ
- Windows 11
- PowerShell 7.x (`pwsh.exe`) — ตรวจสอบด้วย `pwsh --version`
- Claude Code (VS Code extension หรือ CLI)

### ขั้นตอน

```powershell
# 1. เปิด Claude Code ในโฟลเดอร์นี้
# 2. รัน install script
pwsh -NoProfile -File scripts\install.ps1
```

สคริปต์จะ:
- ตรวจสอบว่า PowerShell 7.x ถูกติดตั้ง
- สร้างโฟลเดอร์ `logs/` ถ้ายังไม่มี
- สร้าง `.claude/settings.local.json` พร้อม absolute path ที่ถูกต้อง
- แสดง path ของ log file ทั้งหมด

```powershell
# 3. รัน test เพื่อตรวจสอบว่าทุกอย่างทำงานได้
pwsh -NoProfile -File tests\test_hooks.ps1
# ควรแสดง: PASS 4/4
```

---

## วิธีใช้

หลังติดตั้งแล้ว **ปิดและเปิด Claude Code session ใหม่** hooks จะทำงานอัตโนมัติทุกครั้งที่:

- **ส่ง prompt** → บันทึกลง `logs/prompts.jsonl`
- **จบ response** → บันทึก token usage ลง `logs/usage.jsonl`, `logs/combined.jsonl` และ `logs/summary.log`

ตัวอย่างข้อมูลใน `logs/prompts.jsonl`:
```json
{"timestamp":"2026-04-27T10:00:00+07:00","session_id":"abc123","cwd":"C:\\project","char_count":48,"approx_tokens":14,"prompt":"สวัสดีครับ ช่วยอธิบาย async/await ในภาษา Python หน่อยได้ไหม"}
```

ตัวอย่างข้อมูลใน `logs/usage.jsonl`:
```json
{"timestamp":"2026-04-27T10:00:01+07:00","session_id":"abc123","model":"claude-sonnet-4-6","input_tokens":1234,"output_tokens":567,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"total_tokens":9801}
```

ตัวอย่างข้อมูลใน `logs/combined.jsonl` (prompt + token usage ใน record เดียว):
```json
{"timestamp":"2026-04-27T10:00:01+07:00","session_id":"abc123","model":"claude-sonnet-4-6","prompt":"สวัสดีครับ ช่วยอธิบาย async/await ในภาษา Python หน่อยได้ไหม","input_tokens":1234,"output_tokens":567,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"total_tokens":9801}
```

---

## วิธีดู log

```powershell
# ดู 10 รายการล่าสุด (แบบตาราง)
pwsh -NoProfile -File scripts\view_logs.ps1 -Tail 10

# ดูเฉพาะวันนี้
pwsh -NoProfile -File scripts\view_logs.ps1 -Today

# ดูเฉพาะ session ที่ต้องการ
pwsh -NoProfile -File scripts\view_logs.ps1 -Session "abc123"

# export เป็น JSON
pwsh -NoProfile -File scripts\view_logs.ps1 -Tail 5 -Format json
```

ดู summary แบบข้อความ:
```powershell
Get-Content logs\summary.log
```

---

## วิธี disable hook ชั่วคราว

```powershell
# ปิด hooks
Rename-Item .claude\settings.local.json .claude\settings.local.json.disabled

# เปิด hooks กลับมา
Rename-Item .claude\settings.local.json.disabled .claude\settings.local.json
```

> ต้อง restart Claude Code session หลังจากเปลี่ยนชื่อไฟล์

---

## Troubleshooting

### ปัญหา: Hook ไม่ทำงาน (ไม่มีไฟล์ใน `logs/`)

1. ตรวจสอบสถานะ hooks ใน Claude Code ด้วยคำสั่ง `/hooks`
2. ตรวจสอบว่า `.claude/settings.local.json` มีอยู่และ path ถูกต้อง:
   ```powershell
   Get-Content .claude\settings.local.json | ConvertFrom-Json
   ```
3. รัน install.ps1 ใหม่:
   ```powershell
   pwsh -NoProfile -File scripts\install.ps1
   ```
4. ตรวจสอบ `logs\summary.log` ว่ามี error หรือไม่
5. ต้อง **restart Claude Code session** หลังติดตั้ง hooks ใหม่

---

### ปัญหา: PowerShell 7 ไม่พบ

ติดตั้งผ่าน winget:
```powershell
winget install Microsoft.PowerShell --silent --accept-package-agreements
```

หรือดาวน์โหลดจาก [github.com/PowerShell/PowerShell/releases](https://github.com/PowerShell/PowerShell/releases)

---

## โครงสร้างโปรเจค

```
claude-prompt-logger/
├── .claude/
│   ├── settings.local.json        # hook config (สร้างโดย install.ps1)
│   └── hooks/
│       ├── log_prompt.ps1         # UserPromptSubmit hook
│       ├── log_usage.ps1          # Stop hook
│       └── lib/
│           └── common.ps1         # shared helpers
├── logs/                           # gitignored
│   ├── prompts.jsonl              # prompt ทุกครั้งที่ส่ง
│   ├── usage.jsonl                # token usage ทุก response
│   ├── combined.jsonl             # prompt + token usage ใน record เดียว
│   └── summary.log                # สรุปแบบข้อความอ่านง่าย
├── tests/
│   ├── test_hooks.ps1             # test suite (PASS 4/4)
│   └── fixtures/
│       ├── mock_prompt_payload.json
│       └── mock_transcript.jsonl
├── scripts/
│   ├── install.ps1                # ติดตั้ง/อัพเดต hook settings
│   └── view_logs.ps1              # ดู log แบบตารางหรือ JSON
├── .gitignore
└── README.md
```
