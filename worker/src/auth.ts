import type { Env } from './db';

export function verifyApiKey(req: Request, env: Env): boolean {
  const key = req.headers.get('X-Api-Key');
  return !!env.API_KEY && key === env.API_KEY;
}
