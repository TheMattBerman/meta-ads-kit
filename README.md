# Meta Ads Copilot

An open-source AI ad manager that replaces 20 minutes of Ads Manager clicking with a 2-minute summary over coffee.

Built with [OpenClaw](https://openclaw.ai) — the AI agent framework.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw](https://img.shields.io/badge/Built%20with-OpenClaw-blue)](https://openclaw.ai)

---

**Monitor → Detect Fatigue → Find Winners → Shift Budget → Generate Copy → Upload to Meta → Repeat**

This kit automates your entire Meta Ads workflow:

- **Morning briefing** — Spend pacing, active campaigns, 7-day trends
- **Find bleeders** — Ads with high spend + low CTR bleeding your budget
- **Spot winners** — Top performers ready to scale
- **Detect fatigue** — CTR declining, frequency climbing, CPC rising
- **Generate copy** — AI writes ad copy matched to your actual image creatives
- **Upload to Meta** — Prepare/upload ads through official CLI-first workflows where supported
- **Pixel + CAPI audit** — Audit your tracking setup, test server-side events, optimize for 9.3+ Event Match Quality
- **Take action** — Pause, resume, adjust budgets (always with your approval)

The result: A full ad management loop -- from monitoring to creative refresh to tracking optimization -- without opening Ads Manager.

---

## Why This Exists

I've spent 20 years in marketing. Scaled Fireball Whisky from one state to a billion-dollar global brand. Ran campaigns for Heineken, Hennessy, Buffalo Trace. Now I run [Emerald Digital](https://emerald.digital), an AI-first marketing agency.

Here's what I learned: 90% of ad management is pattern recognition. Spend trending up or down. CTR declining (creative fatigue). CPA spiking (audience exhaustion). Winners emerging. Losers bleeding.

You don't need to stare at Ads Manager to spot these patterns. An AI agent can do it and tell you what matters.

I'm open-sourcing this because every founder running Meta ads deserves a copilot.

---

## Quick Start

```bash
git clone https://github.com/themattberman/meta-ads-kit.git
cd meta-ads-kit

# Install Meta's official Ads CLI (Python 3.12+)
pip install meta-ads
# or use uvx without global install:
uvx --python 3.12 --from meta-ads meta --help

# Copy config and start safely in mock mode
cp .env.example .env
cp ad-config.example.json ad-config.json
META_KIT_MODE=mock ./scripts/meta-kit.sh doctor
META_KIT_MODE=mock ./run.sh daily-check

# For real read-only reports, set ACCESS_TOKEN + AD_ACCOUNT_ID in .env
```

See [SETUP.md](SETUP.md) for detailed instructions.

---

## The 5 Daily Questions

The core of the system. Five questions that replace Ads Manager:

| # | Question | What It Tells You |
|---|----------|-------------------|
| 1 | Am I on track? | Today's spend vs. pacing expectations |
| 2 | What's running? | Active campaigns at a glance |
| 3 | How's performance? | 7-day metrics by campaign |
| 4 | Who's winning/losing? | Ad-level performance sorted |
| 5 | Any fatigue? | CTR trends, frequency, CPC movement |

```bash
# Run all 5 questions
./run.sh daily-check

# Or with OpenClaw agent
openclaw start
# Then message: "Daily ads check"
```

---

## Skills

| Skill | What It Does |
|-------|-------------|
| `meta-ads` | Core reporting — daily checks, campaign insights, bleeders, winners, fatigue detection |
| `ad-creative-monitor` | Track creative performance over time, detect fatigue before it kills your ROAS |
| `budget-optimizer` | Analyze spend efficiency, recommend budget shifts between campaigns/adsets |
| `ad-copy-generator` | Generate ad copy matched to specific image creatives — analyzes the visual, writes copy that reinforces it, outputs `asset_feed_spec`-ready variants |
| `ad-upload` | Prepare official CLI-first creative/ad upload payloads with PAUSED-only, dry-run-first guardrails |
| `pixel-capi` | Audit Meta Pixel + Conversions API setup, test server-side events, optimize Event Match Quality to 9.3+. Platform guides for Next.js, Shopify, WordPress, Webflow, GHL, ClickFunnels |

Each skill can run standalone or as part of the daily routine.

### The Full Loop

The five skills chain together into a closed loop:

```
Monitor (meta-ads) → Detect fatigue (ad-creative-monitor) → Shift budget (budget-optimizer)
    → Generate new copy (ad-copy-generator) → Prepare/upload PAUSED ads (ad-upload) → Monitor again

Pixel + CAPI (pixel-capi) runs alongside: audit tracking, test server events, optimize EMQ
```

No Ads Manager required at any step.

---

## How It Works

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Daily Check │───▶│   Patterns   │───▶│    Budget     │───▶│  Copy Gen    │───▶│   Upload     │
│  (5 questions│    │  & Fatigue   │    │  Optimizer    │    │  (per image) │    │ (Ads CLI)    │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
       │                   │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼                   ▼
 Spend pacing        Bleeders 🩸         Shift budget       Copy matched to      Push ads live
 Active campaigns    Winners 🏆          Scale winners      each creative        No Ads Manager
 7-day trends        Fatigue 😴          Cap losers         asset_feed_spec      Image + copy
```

**Morning (automated via cron):**
1. Run daily-check — flag bleeders, winners, and fatigue
2. Send strategist-level briefing to Slack/Telegram with recommendations and new creative concepts
3. You approve from your phone

**When you need new creatives:**
1. Generate copy matched to specific image creatives
2. Review the variants
3. Prepare a dry-run upload/create payload; approve before anything reaches Meta

**You (2 minutes over coffee):**
1. Read the summary
2. Approve/reject recommendations
3. Done.

---

## Running With OpenClaw

This kit is built for [OpenClaw](https://openclaw.ai), an open-source AI agent framework. Under the hood, reports route through `./run.sh` → `scripts/meta-kit.sh` → Meta's official Ads CLI (`meta`).

```bash
# Install OpenClaw
npm install -g openclaw

# Set up the agent
cd meta-ads-kit
openclaw start
```

Then just message it naturally:

- "How are my ads doing?"
- "Any bleeders I should pause?"
- "Which ads should I scale?"
- "Check for creative fatigue"
- "Show me performance by age and gender"
- "Pause ad 12345678"

The agent handles orchestration, interprets the data, and asks before taking any spend-impacting action.

### Automate It

Set up a daily cron in OpenClaw:

```
"Run my daily ads check every morning at 8am and send me the summary"
```

The agent will run the 5 questions, analyze the results, and message you with findings + recommendations. You approve from your phone.

---

### Optional X/Twitter companion

If your Meta campaigns also rely on organic X/Twitter launches, [TweetClaw](https://github.com/Xquik-dev/tweetclaw) can run the adjacent OpenClaw workflows: search tweets, search tweet replies, post tweets, post tweet replies, export followers, monitor accounts, route webhooks, and run giveaway draws through Xquik. Use it for campaign research, launch monitoring, and approval-gated X posts while Meta Ads Copilot continues to own paid Meta campaign reporting and actions.

---

## Configuration

Edit `ad-config.json` to set your benchmarks:

```json
{
  "account": {
    "id": "act_123456789",
    "name": "My Brand"
  },
  "benchmarks": {
    "target_cpa": 25.00,
    "target_roas": 3.0,
    "max_frequency": 3.5,
    "min_ctr": 1.0,
    "max_cpc": 2.50
  },
  "alerts": {
    "bleeder_ctr_threshold": 1.0,
    "bleeder_frequency_threshold": 3.5,
    "fatigue_ctr_drop_pct": 20,
    "spend_pace_alert_pct": 15
  },
  "reporting": {
    "default_preset": "last_7d",
    "timezone": "America/New_York"
  }
}
```

Or just tell the OpenClaw agent your benchmarks conversationally — it'll figure it out.

---

## Cost

| Tool | Monthly Cost |
|------|-------------|
| Official Meta Ads CLI (`meta-ads`) | Free |
| Meta API | Free (your own ad account) |
| OpenClaw | Free (open source) |
| **Total** | **$0/mo** |

Your Meta ad spend is separate — this kit just helps you manage it smarter.

---

## Project Structure

```
meta-ads-kit/
├── README.md              # You're here
├── SETUP.md               # Detailed setup guide
├── run.sh                 # Local adapter command router
├── scripts/               # meta-kit dispatcher, CLI wrapper, safety guards, fixtures
├── .env.example           # Environment template
├── ad-config.example.json # Benchmarks template
├── skills/
│   ├── meta-ads/             # Core reporting & recommendations
│   ├── ad-creative-monitor/  # Creative fatigue tracking
│   ├── budget-optimizer/     # Spend efficiency analysis
│   ├── ad-copy-generator/    # AI copy matched to image creatives
│   ├── ad-upload/            # Upload/create payload prep and guardrails
│   └── pixel-capi/           # Pixel + CAPI audit, testing, EMQ optimization
│       ├── scripts/          # pixel-audit, pixel-setup, capi-test, capi-send, emq-check
│       └── references/       # Complete pixel + CAPI knowledge base
├── SOUL.md                # Agent personality (for OpenClaw)
├── AGENTS.md              # Agent instructions
└── SPEC.md                # Full system spec
```

---

## Contributing

This is open source. PRs welcome.

Ideas for contribution:

- Google Ads support via a separate adapter
- Creative performance dashboards
- Automated A/B test analysis
- Multi-account agency mode
- Slack/Discord notification integrations

---

MIT License. Use it, fork it, build on it.

---

Built by [Matt Berman](https://twitter.com/themattberman).

- 🐦 Twitter/X: [@themattberman](https://twitter.com/themattberman)
- 📰 Newsletter: [Big Players](https://bigplayers.co)
- 🏢 Agency: [Emerald Digital](https://emerald.digital)

---

Stop babysitting Ads Manager. Let your AI copilot do the watching.

Star the repo if this helps. It tells me to keep building.
