# worker/config.example.ps1
# Copy this file to config.ps1 and fill in your real values.
# config.ps1 is gitignored and will NOT be committed.

# Worker URL after deployment (from: wrangler deploy)
$WORKER_URL     = "https://claude-usage-logger.cloudflare-training3.workers.dev"   # e.g. https://claude-prompt-logger.yourname.workers.dev

# API key — set with: wrangler secret put API_KEY
$WORKER_API_KEY = "Softdebut888"
