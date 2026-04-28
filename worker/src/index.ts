/// <reference types="@cloudflare/workers-types" />

import { verifyApiKey } from './auth';
import { getDashboardData, insertPromptLog, insertUsageLog } from './db';
import type { Env } from './db';
import { dashboardPage } from './dashboard';

export type { Env };

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(req.url);
    const method = req.method;

    if (pathname === '/health') {
      return json({ ok: true });
    }

    if (pathname === '/' && method === 'GET') {
      const data = await getDashboardData(env);
      return new Response(dashboardPage(data), {
        headers: { 'Content-Type': 'text/html;charset=utf-8' },
      });
    }

    if (pathname === '/api/prompt' && method === 'POST') {
      if (!verifyApiKey(req, env)) return json({ ok: false, error: 'Unauthorized' }, 401);
      try {
        const body = (await req.json()) as {
          session_id: string;
          cwd: string;
          char_count: number;
          approx_tokens: number;
          prompt: string;
        };
        await insertPromptLog(env, body);
        return json({ ok: true });
      } catch (err) {
        return json({ ok: false, error: String(err) }, 400);
      }
    }

    if (pathname === '/api/usage' && method === 'POST') {
      if (!verifyApiKey(req, env)) return json({ ok: false, error: 'Unauthorized' }, 401);
      try {
        const body = (await req.json()) as {
          session_id: string;
          model: string;
          input_tokens: number;
          output_tokens: number;
          cache_creation_input_tokens: number;
          cache_read_input_tokens: number;
          total_tokens: number;
        };
        await insertUsageLog(env, body);
        return json({ ok: true });
      } catch (err) {
        return json({ ok: false, error: String(err) }, 400);
      }
    }

    return json({ ok: false, error: 'Not Found' }, 404);
  },
} satisfies ExportedHandler<Env>;
