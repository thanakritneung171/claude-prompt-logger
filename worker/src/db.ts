export interface Env {
  DB: D1Database;
  API_KEY: string;
}

export interface PromptLogRow {
  id: string;
  session_id: string;
  cwd: string;
  char_count: number;
  approx_tokens: number;
  prompt: string;
  logged_at: number;
}

export interface UsageLogRow {
  id: string;
  session_id: string;
  model: string;
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
  total_tokens: number;
  logged_at: number;
}

export interface RecentRow {
  session_id: string;
  model: string;
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
  total_tokens: number;
  logged_at: number;
  prompt: string | null;
  approx_tokens: number | null;
}

export async function insertPromptLog(
  env: Env,
  data: Omit<PromptLogRow, 'id' | 'logged_at'>,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO prompt_logs
       (id, session_id, cwd, char_count, approx_tokens, prompt, logged_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      data.session_id,
      data.cwd,
      data.char_count,
      data.approx_tokens,
      data.prompt,
      Date.now(),
    )
    .run();
}

export async function insertUsageLog(
  env: Env,
  data: Omit<UsageLogRow, 'id' | 'logged_at'>,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO usage_logs
       (id, session_id, model, input_tokens, output_tokens,
        cache_creation_input_tokens, cache_read_input_tokens, total_tokens, logged_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      data.session_id,
      data.model,
      data.input_tokens,
      data.output_tokens,
      data.cache_creation_input_tokens,
      data.cache_read_input_tokens,
      data.total_tokens,
      Date.now(),
    )
    .run();
}

export interface DashboardData {
  totalPrompts: number;
  totalSessions: number;
  grandTotal: number;
  totalInput: number;
  totalOutput: number;
  totalCacheCreate: number;
  totalCacheRead: number;
  avgTokensPerSession: number;
  modelBreakdown: { model: string; sessions: number; tokens: number }[];
  recentRows: RecentRow[];
}

export async function getDashboardData(env: Env): Promise<DashboardData> {
  const [countPrompts, countSessions, tokenTotals, modelBreakdown, recentRows] =
    await Promise.all([
      env.DB.prepare('SELECT COUNT(*) as n FROM prompt_logs').first<{ n: number }>(),
      env.DB.prepare('SELECT COUNT(DISTINCT session_id) as n FROM usage_logs').first<{
        n: number;
      }>(),
      env.DB.prepare(
        `SELECT
           SUM(input_tokens)                as total_input,
           SUM(output_tokens)               as total_output,
           SUM(cache_creation_input_tokens) as total_cache_create,
           SUM(cache_read_input_tokens)     as total_cache_read,
           SUM(total_tokens)                as grand_total
         FROM usage_logs`,
      ).first<{
        total_input: number;
        total_output: number;
        total_cache_create: number;
        total_cache_read: number;
        grand_total: number;
      }>(),
      env.DB.prepare(
        `SELECT model, COUNT(*) as sessions, SUM(total_tokens) as tokens
         FROM usage_logs
         GROUP BY model
         ORDER BY sessions DESC`,
      ).all<{ model: string; sessions: number; tokens: number }>(),
      env.DB.prepare(
        `SELECT
           u.session_id, u.model,
           u.input_tokens, u.output_tokens,
           u.cache_creation_input_tokens, u.cache_read_input_tokens,
           u.total_tokens, u.logged_at,
           (SELECT p.prompt FROM prompt_logs p
            WHERE p.session_id = u.session_id AND p.logged_at <= u.logged_at
            ORDER BY p.logged_at DESC LIMIT 1) as prompt,
           (SELECT p.approx_tokens FROM prompt_logs p
            WHERE p.session_id = u.session_id AND p.logged_at <= u.logged_at
            ORDER BY p.logged_at DESC LIMIT 1) as approx_tokens
         FROM usage_logs u
         ORDER BY u.logged_at DESC
         LIMIT 50`,
      ).all<RecentRow>(),
    ]);

  const sessions = countSessions?.n ?? 0;
  const grand = tokenTotals?.grand_total ?? 0;

  return {
    totalPrompts: countPrompts?.n ?? 0,
    totalSessions: sessions,
    grandTotal: grand,
    totalInput: tokenTotals?.total_input ?? 0,
    totalOutput: tokenTotals?.total_output ?? 0,
    totalCacheCreate: tokenTotals?.total_cache_create ?? 0,
    totalCacheRead: tokenTotals?.total_cache_read ?? 0,
    avgTokensPerSession: sessions > 0 ? Math.round(grand / sessions) : 0,
    modelBreakdown: modelBreakdown.results,
    recentRows: recentRows.results,
  };
}
