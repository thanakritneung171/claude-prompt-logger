import type { DashboardData } from './db';

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function num(n: number): string {
  return n.toLocaleString('en-US');
}

function fmt(ms: number): string {
  return new Date(ms).toLocaleString('en-GB', {
    timeZone: 'Asia/Bangkok',
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function shortId(id: string): string {
  return id.slice(0, 8);
}

function preview(text: string | null, len = 100): string {
  if (!text) return '<span class="muted">—</span>';
  const t = text.trim().replace(/\s+/g, ' ');
  return esc(t.length > len ? t.slice(0, len) + '…' : t);
}

const CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #f5f0e8; color: #2d2006; font-size: 14px; }
  header { background: #1a1200; color: #f5d87a; padding: 16px 24px; display: flex; align-items: center; gap: 12px; }
  header h1 { font-size: 18px; font-weight: 600; letter-spacing: .3px; }
  header span { font-size: 12px; opacity: .6; }
  main { padding: 24px; max-width: 1400px; margin: 0 auto; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; margin-bottom: 28px; }
  .card { background: #fff; border: 1px solid #e8dfc0; border-radius: 8px; padding: 18px 20px; }
  .card .label { font-size: 11px; text-transform: uppercase; letter-spacing: .8px; color: #9a7a2a; font-weight: 600; margin-bottom: 6px; }
  .card .value { font-size: 28px; font-weight: 700; color: #1a1200; line-height: 1; }
  section { margin-bottom: 28px; }
  section h2 { font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: .6px; color: #9a7a2a; margin-bottom: 12px; }
  table { width: 100%; border-collapse: collapse; background: #fff; border: 1px solid #e8dfc0; border-radius: 8px; overflow: hidden; }
  th { background: #faf6ec; padding: 9px 12px; text-align: left; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .6px; color: #9a7a2a; border-bottom: 1px solid #e8dfc0; white-space: nowrap; }
  td { padding: 8px 12px; border-bottom: 1px solid #f0e8d0; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #fdf9ef; }
  .mono { font-family: monospace; font-size: 12px; color: #6a5010; }
  .muted { color: #c0a860; }
  .tag { display: inline-block; background: #fef3c7; color: #92400e; border-radius: 4px; padding: 1px 7px; font-size: 11px; font-weight: 600; white-space: nowrap; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .prompt-cell { max-width: 300px; word-break: break-word; color: #3d2d00; line-height: 1.45; }
`;

export function dashboardPage(data: DashboardData): string {
  const kpiCards = [
    { label: 'Total Prompts', value: num(data.totalPrompts) },
    { label: 'Sessions', value: num(data.totalSessions) },
    { label: 'Total Tokens', value: num(data.grandTotal) },
    { label: 'Avg / Session', value: num(data.avgTokensPerSession) },
    { label: 'Input', value: num(data.totalInput) },
    { label: 'Output', value: num(data.totalOutput) },
    { label: 'Cache Write', value: num(data.totalCacheCreate) },
    { label: 'Cache Read', value: num(data.totalCacheRead) },
  ];

  const modelRows = data.modelBreakdown
    .map(
      (m) =>
        `<tr>
          <td><span class="tag">${esc(m.model)}</span></td>
          <td class="num">${num(m.sessions)}</td>
          <td class="num">${num(m.tokens)}</td>
        </tr>`,
    )
    .join('');

  const recentRows = data.recentRows
    .map(
      (r) =>
        `<tr>
          <td class="mono" style="white-space:nowrap">${fmt(r.logged_at)}</td>
          <td class="mono">${shortId(r.session_id)}</td>
          <td><span class="tag">${esc(r.model)}</span></td>
          <td class="prompt-cell">${preview(r.prompt)}</td>
          <td class="num">${num(r.input_tokens)}</td>
          <td class="num">${num(r.output_tokens)}</td>
          <td class="num">${num(r.cache_creation_input_tokens)}</td>
          <td class="num">${num(r.cache_read_input_tokens)}</td>
          <td class="num" style="font-weight:600">${num(r.total_tokens)}</td>
        </tr>`,
    )
    .join('');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>Claude Prompt Logger</title>
  <style>${CSS}</style>
</head>
<body>
  <header>
    <h1>Claude Prompt Logger</h1>
    <span>auto-refresh every 60s</span>
  </header>
  <main>
    <div class="grid">
      ${kpiCards.map((c) => `<div class="card"><div class="label">${c.label}</div><div class="value">${c.value}</div></div>`).join('\n      ')}
    </div>

    <section>
      <h2>Model Breakdown</h2>
      <table>
        <thead><tr><th>Model</th><th class="num">Sessions</th><th class="num">Tokens</th></tr></thead>
        <tbody>${modelRows || '<tr><td colspan="3" class="muted" style="padding:16px">No data yet</td></tr>'}</tbody>
      </table>
    </section>

    <section>
      <h2>Recent Activity (last 50)</h2>
      <table>
        <thead>
          <tr>
            <th>Time (BKK)</th>
            <th>Session</th>
            <th>Model</th>
            <th>Prompt</th>
            <th class="num">Input</th>
            <th class="num">Output</th>
            <th class="num">Cache↑</th>
            <th class="num">Cache↓</th>
            <th class="num">Total</th>
          </tr>
        </thead>
        <tbody>${recentRows || '<tr><td colspan="9" class="muted" style="padding:16px">No data yet</td></tr>'}</tbody>
      </table>
    </section>
  </main>
</body>
</html>`;
}
