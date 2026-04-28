# Worker Architecture

## โครงสร้างโปรเจค

```
worker/
├── wrangler.jsonc          # Cloudflare Worker config (D1 binding, port)
├── package.json            # scripts: dev, deploy, db:apply
├── tsconfig.json           # TypeScript config (target: esnext, bundler resolution)
├── schema.sql              # D1 DDL — สร้าง prompt_logs + usage_logs
├── config.example.ps1      # template config สำหรับ hook (committed)
├── config.ps1              # ค่าจริง: WORKER_URL + WORKER_API_KEY (gitignored)
├── .dev.vars               # local dev secrets สำหรับ wrangler dev (gitignored)
└── src/
    ├── index.ts            # entry point — request router
    ├── auth.ts             # verifyApiKey()
    ├── db.ts               # D1 helpers + types + dashboard queries
    └── dashboard.ts        # HTML generator (dashboardPage, clearPage)
```

---

## Data Flow

```
Claude Code hook (PowerShell)
    │
    ├─ log_prompt.ps1 ──► POST /api/prompt ──► insertPromptLog() ──► prompt_logs
    │
    └─ log_usage.ps1  ──► POST /api/usage  ──► insertUsageLog()  ──► usage_logs
                                                                          │
Browser ──────────────────► GET /          ──► getDashboardData() ◄──────┘
                                                      │
                                               dashboardPage(data)
                                                      │
                                                  HTML response
```

---

## src/index.ts — Router

Worker ไม่ใช้ framework — routing ทำด้วย `if/else` บน `pathname` และ `method`:

| Method | Path | Auth | Handler |
|--------|------|------|---------|
| GET | `/` | — | `getDashboardData()` → `dashboardPage()` |
| GET | `/health` | — | `{ ok: true }` |
| GET | `/clear` | — | `clearPage()` |
| POST | `/clear` | form `api_key` | `clearAllLogs()` → redirect `/?cleared=1` |
| POST | `/api/prompt` | `X-Api-Key` | `insertPromptLog()` |
| POST | `/api/usage` | `X-Api-Key` | `insertUsageLog()` |

**Auth สองแบบ:**
- POST `/api/*` — ใช้ `verifyApiKey()` ตรวจ header `X-Api-Key`
- POST `/clear` — รับ `api_key` จาก HTML form body (`formData()`) เพราะ browser form ส่ง custom header ไม่ได้

---

## src/auth.ts

```typescript
export function verifyApiKey(req: Request, env: Env): boolean {
  return !!env.API_KEY && req.headers.get('X-Api-Key') === env.API_KEY;
}
```

`env.API_KEY` มาจาก Wrangler secret (production) หรือ `.dev.vars` (local dev) — ไม่เคยอยู่ใน source code

---

## src/db.ts — D1 Helpers

### `insertPromptLog(env, data)`
INSERT เข้า `prompt_logs` — `id` ใช้ `crypto.randomUUID()`, `logged_at` ใช้ `Date.now()`

### `insertUsageLog(env, data)`
INSERT เข้า `usage_logs` — เหมือนกัน

### `clearAllLogs(env)`
`env.DB.batch([DELETE FROM prompt_logs, DELETE FROM usage_logs])` — ลบพร้อมกันใน transaction เดียว

### `getDashboardData(env)`
รัน 5 queries พร้อมกันด้วย `Promise.all()`:

```
1. COUNT(*) FROM prompt_logs                    → totalPrompts
2. COUNT(DISTINCT session_id) FROM usage_logs   → totalSessions
3. SUM(tokens...) FROM usage_logs               → token breakdown
4. GROUP BY model FROM usage_logs               → modelBreakdown[]
5. JOIN usage_logs + correlated prompt subquery → recentRows[] (50 รายการ)
```

**Query ที่ 5 (สำคัญ)** — จับคู่ prompt กับ usage โดยใช้ `logged_at`:
```sql
SELECT u.*, (
  SELECT p.prompt FROM prompt_logs p
  WHERE p.session_id = u.session_id
    AND p.logged_at <= u.logged_at   -- prompt ที่ส่งก่อนหรือพร้อมกับ usage นี้
  ORDER BY p.logged_at DESC LIMIT 1  -- ล่าสุดที่ตรงเงื่อนไข
) as prompt
FROM usage_logs u
ORDER BY u.logged_at DESC LIMIT 50
```

เหตุผล: ใน session เดียวกันมีหลาย prompt+usage — ถ้าใช้ `MAX(rowid)` จะได้ prompt ล่าสุดของทั้ง session มาทับทุก row แทนที่จะได้ prompt ที่ตรงกับ usage นั้นๆ

---

## src/dashboard.ts — HTML Generator

ทุกหน้าเป็น server-rendered HTML ส่งกลับเป็น string — ไม่มี client-side framework

### `dashboardPage(data, cleared?)`

โครงสร้าง HTML:
```
<header>          — ชื่อ + auto-refresh label + ปุ่ม Clear Data
<div.grid>        — KPI cards: Prompts, Sessions, Total Tokens, Avg/Session, Input, Output, Cache↑, Cache↓
<section>         — Model Breakdown table (GROUP BY model)
<section>         — Recent Activity table (50 rows, JOIN prompt+usage)
[#popup-overlay]  — modal "ลบเรียบร้อย" (แสดงเฉพาะเมื่อ cleared=true)
```

**Auto-refresh:** `<meta http-equiv="refresh" content="60">` — ไม่ใช้ JS polling

**Cleared popup:** เมื่อ `cleared=true` (จาก `?cleared=1` query param) จะ render:
```html
<div id="popup-overlay">   <!-- backdrop -->
  <div id="popup">
    ✅ ลบข้อมูลเรียบร้อยแล้ว
    <a href="/">ตกลง</a>   <!-- ลบ query param ออก → popup หาย -->
  </div>
</div>
```
กดตกลง → navigate ไป `/` (ไม่มี `?cleared=1`) → popup ไม่ถูก render → หาย

### `clearPage(error?)`

ฟอร์มขอ API Key ก่อนลบ:
```
<form method="POST" action="/clear">
  <input type="password" name="api_key">
  <button type="submit">ลบข้อมูลทั้งหมด</button>
</form>
```
ถ้า key ผิด → render หน้าเดิมพร้อม error message (ไม่ redirect)

---

## Security

| จุด | วิธีป้องกัน |
|-----|-----------|
| POST /api/* | `X-Api-Key` header ต้องตรงกับ Wrangler secret |
| POST /clear | `api_key` ใน form body ต้องตรงกับ secret |
| GET / (dashboard) | เปิดสาธารณะ — แสดงแค่ aggregate stats + prompt preview 100 ตัวอักษร |
| HTML output | ทุก user input ผ่าน `esc()` ก่อน render (prevent XSS) |
| Secrets | ไม่เคยอยู่ใน wrangler.jsonc — ใช้ `wrangler secret put` เท่านั้น |

---

## Local Development

```bash
cd worker
npm install
npm run db:apply:local   # สร้าง tables ใน local SQLite
npm run dev              # http://localhost:8790
```

`.dev.vars` ถูก wrangler อ่านอัตโนมัติ — `API_KEY` จะพร้อมใช้งาน

ทดสอบ POST:
```powershell
Invoke-RestMethod http://localhost:8790/api/prompt `
  -Method POST `
  -Headers @{"X-Api-Key"="Softdebut888"} `
  -Body '{"session_id":"test","cwd":"C:\\","char_count":4,"approx_tokens":2,"prompt":"test"}' `
  -ContentType "application/json"
```

---

## Deployment

```bash
wrangler secret put API_KEY   # ใส่ key จริง (ทำครั้งเดียว)
npm run db:apply              # สร้าง tables บน D1 remote (ทำครั้งเดียว)
npm run deploy                # deploy ทุกครั้งที่แก้โค้ด
```
