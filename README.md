# claude-prompt-logger

บันทึก prompt ทุกครั้งที่ส่งใน Claude Code พร้อมจำนวน token และ usage — เก็บทั้งลงไฟล์ JSONL ในเครื่องและส่งขึ้น Cloudflare D1 ผ่าน Worker พร้อม dashboard แสดงสถิติ

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
│           └── common.ps1         # shared helpers (Write-LogEntry, Send-LogToWorker ฯลฯ)
├── logs/                          # gitignored
│   ├── prompts.jsonl              # prompt ทุกครั้งที่ส่ง
│   ├── usage.jsonl                # token usage ทุก response
│   ├── combined.jsonl             # prompt + token usage ใน record เดียว
│   └── summary.log               # สรุปแบบข้อความอ่านง่าย
├── worker/                        # Cloudflare Worker + Dashboard
│   ├── src/
│   │   ├── index.ts              # router
│   │   ├── auth.ts               # API key verification
│   │   ├── db.ts                 # D1 helpers + queries
│   │   └── dashboard.ts          # server-rendered HTML
│   ├── schema.sql                # D1 table definitions
│   ├── wrangler.jsonc            # Worker config
│   ├── config.example.ps1        # template config สำหรับ hook
│   ├── config.ps1                # ค่าจริง (gitignored)
│   ├── .dev.vars                 # local dev secrets (gitignored)
│   └── ARCHITECTURE.md           # อธิบาย logic ของ worker
├── scripts/
│   ├── install.ps1               # ติดตั้ง/อัพเดต hook settings
│   └── view_logs.ps1             # ดู log แบบตารางหรือ JSON
├── tests/
│   ├── test_hooks.ps1            # test suite (PASS 4/4)
│   └── fixtures/
├── INTEGRATION.md                # คู่มือเชื่อมต่อจากโปรเจคอื่น
├── .gitignore
└── README.md
```

---

## วิธีติดตั้ง (Hook)

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

```powershell
# 3. รัน test เพื่อตรวจสอบ
pwsh -NoProfile -File tests\test_hooks.ps1
# ควรแสดง: PASS 4/4
```

---

## วิธีติดตั้ง (Worker + D1)

### ความต้องการเพิ่มเติม
- Node.js 18+
- Cloudflare account + Wrangler CLI (`npm i -g wrangler`)

### ขั้นตอน

```bash
cd worker
npm install

# สร้าง tables บน D1 (ทำครั้งเดียว)
npm run db:apply

# ตั้ง API Key บน Cloudflare (ทำครั้งเดียว)
wrangler secret put API_KEY

# Deploy
npm run deploy
```

หลัง deploy:
1. Copy `worker/config.example.ps1` → `worker/config.ps1`
2. ใส่ Worker URL และ API Key ที่ตั้งไว้

```powershell
# worker/config.ps1
$WORKER_URL     = "https://claude-prompt-logger.xxx.workers.dev"
$WORKER_API_KEY = "your-api-key"
```

---

## วิธีใช้

หลังติดตั้งแล้ว **ปิดและเปิด Claude Code session ใหม่** hooks จะทำงานอัตโนมัติทุกครั้งที่:

- **ส่ง prompt** → บันทึกลง `logs/prompts.jsonl` + ส่งขึ้น D1 ผ่าน Worker
- **จบ response** → บันทึก token usage ลง `logs/usage.jsonl`, `logs/combined.jsonl`, `logs/summary.log` + ส่งขึ้น D1

> JSONL ไฟล์ในเครื่องยังคงทำงานเป็น fallback เสมอ แม้ Worker จะไม่พร้อมใช้งาน

### Dashboard

เปิดในเบราว์เซอร์ที่ Worker URL เพื่อดูสถิติ:
- KPI: จำนวน prompts, sessions, total tokens, avg tokens/session
- Model breakdown
- Recent activity 50 รายการ (prompt + token breakdown)
- ปุ่ม Clear Data (ต้องใส่ API Key ยืนยัน)

---

## วิธีดู log (local)

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

## เอกสารเพิ่มเติม

| ไฟล์ | เนื้อหา |
|------|---------|
| [INTEGRATION.md](INTEGRATION.md) | คู่มือเชื่อมต่อจากโปรเจคอื่น (endpoints, ตัวอย่างโค้ด) |
| [worker/ARCHITECTURE.md](worker/ARCHITECTURE.md) | อธิบายโครงสร้าง Worker, logic dashboard, security |

---

## Troubleshooting

### Hook ไม่ทำงาน (ไม่มีไฟล์ใน `logs/`)

1. ตรวจสอบ hooks ใน Claude Code ด้วย `/hooks`
2. ตรวจสอบ `.claude/settings.local.json`:
   ```powershell
   Get-Content .claude\settings.local.json | ConvertFrom-Json
   ```
3. รัน install.ps1 ใหม่
4. ตรวจสอบ `logs\summary.log` ว่ามี error หรือไม่
5. **Restart Claude Code session**

### Worker ไม่รับข้อมูล

1. ตรวจสอบ `config.ps1` มี URL และ API Key ถูกต้อง
2. ทดสอบ connectivity:
   ```powershell
   Invoke-RestMethod "$WORKER_URL/health"
   # ควรได้: @{ok=True}
   ```
3. ตรวจสอบ API Key ตรงกับที่ตั้งใน Cloudflare:
   ```bash
   wrangler secret list
   ```

### PowerShell 7 ไม่พบ

```powershell
winget install Microsoft.PowerShell --silent --accept-package-agreements
```
