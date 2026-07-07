# Nidhi — निधि

*Nidhi* (treasure, a fund kept safely) is a **private, on-device personal-finance app for iOS** — built for Indian banking, ₹/INR-first.
No backend, no analytics, no third-party SDKs. Everything — your transactions, balances, statements,
even the AI summaries — is processed on your device.

## What it does

| Area | Highlights |
|------|-----------|
| **Net worth** | Banks + cards + deposits + investments, daily history, milestone ladder |
| **Statement import** | Password-protected bank/card PDF statements (HDFC, Federal, Axis, ICICI, Scapia…) parsed on-device, including combined statements with FDs/RDs |
| **Gmail auto-import** | Read-only OAuth scan of transaction-alert emails and statement attachments |
| **Smart categorisation** | Fuzzy merchant→category library + your own rules; per-transaction rewards and international/forex capture |
| **Budgets** | Per-category caps (monthly / quarterly / annual / custom), period navigation (month, YTD, FYTD, FY), drill-in to transactions |
| **Investments** | Live prices from Yahoo Finance (stocks/ETFs) and AMFI (mutual funds) — free, no API keys |
| **Goals** | Back goals with real assets so progress updates itself; light XP/levels/badges |
| **Income & tax** | Income streams, payslip import, a real Indian slab engine (both regimes compared) |
| **AI insights** | Opt-in, off by default; on-device Apple Intelligence or your own key — only aggregates ever leave the device |

## Privacy stance

- All data lives in local storage on your iPhone; secrets (OAuth tokens, PDF passwords) live in the iOS Keychain.
- Nothing is uploaded anywhere. Backups go to your own Files/iCloud Drive.
- AI features are **opt-in and off by default**; when enabled, only aggregate figures (category totals, goal progress) are sent — never raw transactions or account numbers. On-device providers (Apple Intelligence, local Ollama) keep even that local.

## Where to start

- New to the app → [Getting started](guide/getting-started.md)
- Pulling in your bank data → [Importing statements](guide/importing-statements.md) and [Gmail & bank sync](guide/gmail-and-bank-sync.md)
- Something looks off → [Troubleshooting](guide/troubleshooting.md)
- Hacking on the code → the **Developer** section (start with `AGENTS.md` in the repo root)

> **Status:** personal project, open-sourced, no warranty. Not affiliated with any bank, Google, Yahoo, AMFI, or Setu.
