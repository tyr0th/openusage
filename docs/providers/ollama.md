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

1. **A browser session cookie** (macOS Keychain, service `ollama-session-cookie`, account `catalyst`) — kept fresh by a separate, independently-run tool: a headless-Playwright cookie-refresher LaunchAgent that re-authenticates against `ollama.com` on its own schedule and writes the cookie to Keychain. **This refresher is not part of OpenUsage** — it lives in the Catalyst `openusage` repo (`scripts/ollama-cookie-refresher/`, not this SwiftPM tree) and must be installed and running separately there; see its own `README.md` for setup. With a valid cookie, OpenUsage scrapes the rendered `ollama.com/settings` page for the Session/Weekly percentages, their reset times, and your plan tier.
2. **An Ollama Cloud API key** (Keychain, service `ollama-api-key`, account `catalyst`), used two ways: alongside a valid session cookie it adds the best-effort Models badge; with no session cookie at all it becomes the whole story — OpenUsage calls `/v1/models` and *infers* a plan tier from whether any known Pro-only model is present, defaulting to `Free`. This inference is a heuristic, not authoritative.
3. `OLLAMA_SESSION_COOKIE` / `OLLAMA_API_KEY` / `OLLAMA_PLAN` environment variables, as a manual override for either credential kind and an explicit plan-name override respectively (`OLLAMA_PLAN` must be one of `free`/`pro`/`team`/`enterprise`; anything else is ignored).

## Troubleshooting

- **"No Ollama API key found..."** — neither a session cookie nor an API key was found anywhere above. Set up the cookie-refresher LaunchAgent in the Catalyst `openusage` repo (recommended, gives live Session/Weekly meters) or add an API key to Keychain.
- **"Session cookie expired..."** — `ollama.com/settings` either redirected to sign-in or returned a sign-in page directly. The external refresher LaunchAgent should pick this up on its next tick; its `refresh_session.py` (in the Catalyst `openusage` repo) re-runs it manually.
- **"API key invalid..."** — the API key was rejected by `/v1/models`; generate a fresh one from your Ollama Cloud account settings.
- **Plan/Models missing on the cookie path** — the Models badge only appears if an API key is *also* configured; it's best-effort and never blocks the Session/Weekly meters.

## Under the hood

Primary path: `GET https://ollama.com/settings` with the session cookie (`Cookie: __Secure-session=<value>`); redirects are not followed, since a 302/303 to sign-in is how a stale cookie is usually detected. As a defensive fallback, a 200 response is also treated as an expired session if its body looks like a sign-in page rather than the settings page (no usage markers, and a sign-in-page giveaway) — some deployments serve the sign-in page directly rather than redirecting to it. The response HTML is scraped for the `Session usage` / `Weekly usage` labels (a `NN.N% used` figure and a `data-time="..."` reset timestamp shortly after each) and the `Cloud Usage` plan tier. Fallback path (no cookie): `GET https://ollama.com/v1/models` with the API key, inferring plan from the model catalog.

> There is no documented usage API for Ollama Cloud, so the primary path is a page scrape of `ollama.com/settings` rather than a stable API contract — a redesign of that page can silently break the Session/Weekly/Plan figures. This is a known, accepted trade-off for this provider, not a defect.
