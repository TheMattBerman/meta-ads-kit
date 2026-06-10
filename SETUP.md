# Meta Ads Copilot — Setup Guide

Get the local Meta Ads operator running safely in mock mode first, then read-only mode.

---

## Step 1: Install the official Meta Ads CLI

Meta's official Ads CLI is published as the Python package `meta-ads`.

Requirements:
- Python 3.12+
- `pip`
- `uv` recommended

```bash
pip install meta-ads
# or run without global install:
uvx --python 3.12 --from meta-ads meta --help
```

Verify:

```bash
meta --help
meta ads --help
meta ads campaign list --help
meta ads insights get --help
```

---

## Step 2: Start in mock mode

```bash
cp .env.example .env
cp ad-config.example.json ad-config.json
META_KIT_MODE=mock ./scripts/meta-kit.sh doctor
META_KIT_MODE=mock ./run.sh daily-check
```

Mock mode uses local fixtures only. It does not call Meta.

---

## Step 3: Configure official Ads CLI auth for read-only use

Ads CLI authenticates with a Meta **admin system user access token**.

Create a system user in Meta Business Suite, assign the needed assets, generate a token, then set:

```bash
ACCESS_TOKEN=<SYSTEM_USER_ACCESS_TOKEN>
AD_ACCOUNT_ID=act_YOUR_ACCOUNT_ID
BUSINESS_ID=<OPTIONAL_BUSINESS_ID>
```

Minimum read-only scopes for monitoring:
- `ads_read`
- `read_insights`

Additional scopes are needed only for management/catalog/page workflows:
- `ads_management`
- `business_management`
- `pages_show_list`
- `pages_read_engagement`
- `pages_manage_ads`
- `catalog_management`

Never commit `.env`, `.env.*.local`, tokens, or secrets.

---

## Step 4: Configure benchmarks

```bash
cp ad-config.example.json ad-config.json
```

Edit `ad-config.json` with your targets:

```json
{
  "account": {
    "id": "act_YOUR_ACCOUNT_ID",
    "name": "Your Brand Name"
  },
  "benchmarks": {
    "target_cpa": 25.00,
    "target_roas": 3.0,
    "max_frequency": 3.5,
    "min_ctr": 1.0,
    "max_cpc": 2.50
  }
}
```

---

## Step 5: Run read-only reports

After auth is configured:

```bash
META_KIT_MODE=read-only ./scripts/meta-kit.sh doctor
META_KIT_MODE=read-only ./run.sh campaigns
META_KIT_MODE=read-only ./run.sh overview --preset last_7d
META_KIT_MODE=read-only ./run.sh daily-check
```

The adapter writes sanitized read-only snapshots under `local/outputs/read-only/`.

### How live reports are sourced

- **Campaign list** comes from the official Ads CLI (`meta ads campaign list`).
- **Insights breakdowns** (per-campaign, per-ad, pacing, fatigue) come from the
  Meta Marketing API (Graph) using the same `ACCESS_TOKEN`. The official Ads CLI
  `insights get` is account-level only (no `--level`), so it cannot produce
  per-campaign/per-ad rows in one call; the Graph API can. See
  `scripts/lib/live-adapter.sh`. Override the version with `GRAPH_API_VERSION`
  (default `v21.0`).

`.env` values do **not** override variables already set on the command line, so
`META_KIT_MODE=mock ./run.sh daily-check` always forces mock regardless of `.env`.

## Multi-brand / multi-client

Each report reads `AD_ACCOUNT_ID` (and `ACCESS_TOKEN`) at call time, so you can
run multiple brands without editing files. Two patterns:

```bash
# A) Inline per-run (same token, different account):
AD_ACCOUNT_ID=act_1111111111 ./run.sh daily-check
AD_ACCOUNT_ID=act_2222222222 ./run.sh daily-check

# B) Per-client env files (different tokens per client):
#    .env.clienta.local  -> ACCESS_TOKEN + AD_ACCOUNT_ID for client A
#    .env.clientb.local  -> ACCESS_TOKEN + AD_ACCOUNT_ID for client B
META_KIT_ENV_FILE=.env.clienta.local ./run.sh daily-check
META_KIT_ENV_FILE=.env.clientb.local ./run.sh daily-check
```

All `.env` and `.env.*.local` files are gitignored — tokens never get committed.

## Tests

```bash
./scripts/test/test_live_adapter.sh   # offline unit tests for the live adapter transform
```

---

## Mutations: approval-only

Mutating work is blocked by default.

Rules:
- default mode is `mock`
- read-only mode cannot mutate
- live mutation requires `META_KIT_MODE=live-approved`
- live mutation requires `META_KIT_APPROVAL_ID`
- creates must be `PAUSED`
- deletes remain unsupported in v1
- every proposed mutation writes a dry-run artifact first

Dry-run example:

```bash
META_KIT_MODE=mock ./scripts/meta-kit.sh create-ad --payload examples/create-ad.json --dry-run
```

---

## Run With OpenClaw

```bash
npm install -g openclaw
cd meta-ads-kit
openclaw start
```

Ask naturally:
- "How are my ads doing?"
- "Any bleeders?"
- "Daily check"
- "Check for fatigue"

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `meta: command not found` | Install `meta-ads` or use `uvx --python 3.12 --from meta-ads meta ...` |
| Python version error | Use Python 3.12+ |
| `ACCESS_TOKEN` missing | Add a system user token to `.env` or environment |
| `AD_ACCOUNT_ID` missing | Set `AD_ACCOUNT_ID=act_...` |
| No data returned | Confirm campaigns ran during the selected date range |
| Rate limited | Wait and retry; use narrower reports |

Check everything:

```bash
./scripts/meta-kit.sh doctor
```
