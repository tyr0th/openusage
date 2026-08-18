# Higgsfield

Tracks your Higgsfield account using the login the `higgsfield` CLI already stored on your Mac. Nothing is
sent anywhere except Higgsfield's own balance endpoint.

## What it tracks

| Metric | Meaning |
|---|---|
| Credits | Credits remaining on your account |
| Plan | Your subscription plan (e.g. Plus) |

Higgsfield's API exposes only your credit balance and plan — there's no per-window allowance or reset — so
OpenUsage shows an honest Credits **count** (not a percentage meter, since there's no denominator to fill)
and your plan. No Session/Weekly bar is invented.

## Where credentials come from

Run `higgsfield auth login` as usual. OpenUsage reads the access token the CLI writes to
`~/.config/higgsfield/credentials.json` (or `$HIGGSFIELD_CONFIG_DIR/credentials.json` if you've set it).
There's no login prompt in the app and no token to paste.

## Troubleshooting

- **"Not signed in to Higgsfield"** — run `higgsfield auth login`, then refresh.
- **"Higgsfield login expired"** — your stored access token expired. Run `higgsfield auth login` again to
  refresh it, then refresh OpenUsage. (OpenUsage does not refresh the token itself; the CLI owns that flow.)

## Under the hood

`GET https://fnf.higgsfield.ai/agents/balance` with the stored access token as a bearer credential, returning
your remaining `credits` and `subscription_plan_type`. Read-only. A `401` is surfaced as the expired-login
message above rather than a silent blank.
