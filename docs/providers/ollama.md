# Ollama

Tracks Ollama Cloud (`ollama.com`) subscription usage — not a local Ollama daemon.

## What it tracks

| Metric | Meaning |
|---|---|
| Session | Rolling ~5-hour window usage (percent) |
| Weekly | 7-day window usage (percent) |
| Plan | Your Ollama Cloud tier (`Free`, `Pro`, `Team`, `Enterprise`) |
| Models | Count of models available to your account (best-effort) |

## Where credentials come from

Ollama Cloud has no companion CLI or desktop app that stores a long-lived local credential the way Claude Code, Codex, or Cursor do, and there is no documented usage API. OpenUsage instead reads:

1. **A browser session cookie** (macOS Keychain, service `ollama-session-cookie`, account `catalyst`) — kept fresh by a separate, independently-run tool: `scripts/ollama-cookie-refresher/`, a headless-Playwright LaunchAgent that re-authenticates against `ollama.com` on its own schedule and writes the cookie to Keychain. **This refresher is not part of OpenUsage** — it must be installed and running separately; see its own `README.md` for setup. With a valid cookie, OpenUsage scrapes the rendered `ollama.com/settings` page for the Session/Weekly percentages, their reset times, and your plan tier.
2. **An Ollama Cloud API key** (Keychain, service `ollama-api-key`, account `catalyst`), used two ways: alongside a valid session cookie it adds the best-effort Models badge; with no session cookie at all it becomes the whole story — OpenUsage calls `/v1/models` and *infers* a plan tier from whether any known Pro-only model is present, defaulting to `Free`. This inference is a heuristic, not authoritative.
3. `OLLAMA_SESSION_COOKIE` / `OLLAMA_API_KEY` / `OLLAMA_PLAN` environment variables, as a manual override for either credential kind and an explicit plan-name override respectively (`OLLAMA_PLAN` must be one of `free`/`pro`/`team`/`enterprise`; anything else is ignored).

## Troubleshooting

- **"No Ollama API key found..."** — neither a session cookie nor an API key was found anywhere above. Set up `scripts/ollama-cookie-refresher/` (recommended, gives live Session/Weekly meters) or add an API key to Keychain.
- **"Session cookie expired..."** — `ollama.com/settings` redirected to sign-in. The external refresher LaunchAgent should pick this up on its next tick; `scripts/ollama-cookie-refresher/refresh_session.py` re-runs it manually.
- **"API key invalid..."** — the API key was rejected by `/v1/models`; generate a fresh one from your Ollama Cloud account settings.
- **Plan/Models missing on the cookie path** — the Models badge only appears if an API key is *also* configured; it's best-effort and never blocks the Session/Weekly meters.

## Under the hood

Primary path: `GET https://ollama.com/settings` with the session cookie (`Cookie: __Secure-session=<value>`); redirects are not followed, since a 302/303 to sign-in is exactly how a stale cookie is detected. The response HTML is scraped for the `Session usage` / `Weekly usage` labels (a `NN.N% used` figure and a `data-time="..."` reset timestamp shortly after each) and the `Cloud Usage` plan tier. Fallback path (no cookie): `GET https://ollama.com/v1/models` with the API key, inferring plan from the model catalog.

> There is no documented usage API for Ollama Cloud, so the primary path is a page scrape of `ollama.com/settings` rather than a stable API contract — a redesign of that page can silently break the Session/Weekly/Plan figures. This is a known, accepted trade-off for this provider, not a defect.
