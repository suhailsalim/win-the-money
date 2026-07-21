# Execution plans

Self-contained implementation plans, written so a less capable model can execute them without
questions. Each has: goal, exact files, step order, edge cases found during exploration, and
verifiable acceptance criteria.

**This file is the index of record.** Status below was re-verified against the code on 2026-07-15.
Don't trust a plan's own `Rank: X of Y` header — those still carry the original pre-#14 numbering and
no longer match this list.

## Core improvements (ranked — do in order)

1. [PLAN-parser-regression-harness.md](PLAN-parser-regression-harness.md) — checked-in one-command
   parser test harness. **Prerequisite for parser work.** Scope has shrunk: the HDFC EMI-marker fix it
   was written to land already shipped in #14, so step 1 is done — this is now the harness + assertions
   only. Note the four fixture PDFs are gitignored, so they exist only in the main working copy, not in
   worktrees.
2. [PLAN-backup-rotation-and-safety.md](PLAN-backup-rotation-and-safety.md) — rotating backups,
   overwrite sanity gate, restore preview. `BackupManager` still writes a single fixed
   `WinTheMoney-backup.json`; no rotation exists.
3. [PLAN-plan-period-cap-snapshots.md](PLAN-plan-period-cap-snapshots.md) — truthful historical
   budget caps.
4. [PLAN-axis-scapia-per-txn-rewards.md](PLAN-axis-scapia-per-txn-rewards.md) — EDGE Miles per-txn
   parsing (needs #1). Still open despite #11/#12: `parseHDFC` and `parseICICI` emit per-row rewards,
   but `parseAxis`/`parseScapia` capture only the *account-level* balance via `cardAccount(reward:)`.
   #12 did Axis MCC + forex, not rewards.

## Missing features (ranked)

1. [PLAN-subscription-reminders.md](PLAN-subscription-reminders.md) — recurring-charge prediction.
   Partly there: `Store.recurringGroups` already groups recurring transfers; prediction + reminders
   are missing.
2. [PLAN-global-search.md](PLAN-global-search.md) — transaction search & filters. Nothing searchable
   exists anywhere in the app yet.
3. [PLAN-txn-export.md](PLAN-txn-export.md) — CSV/JSON export. **Partly shipped:** Settings →
   "Export transactions (CSV)" works via `Store.transactionsCSV()`, but with 6 of the planned 14
   columns, no JSON DTO, no UTF-8 BOM (so ₹ mojibakes in Excel), no filtered/toolbar export, and no
   `TxnExporter.swift`.
4. [PLAN-cashflow-forecast.md](PLAN-cashflow-forecast.md) — safe-to-spend projection. Needs #1 above;
   its other dependency (card due dates) shipped in #17.
5. [PLAN-loans-emi-tracking.md](PLAN-loans-emi-tracking.md) — loans as liabilities
6. [PLAN-monthly-report.md](PLAN-monthly-report.md) — shareable month-in-review
7. [PLAN-app-intents-quick-log.md](PLAN-app-intents-quick-log.md) — Siri/Shortcuts quick logging
8. [PLAN-cloudkit-sync.md](PLAN-cloudkit-sync.md) — multi-device sync (needs paid dev team; do last)

## Web

- [PLAN-website.md](PLAN-website.md) — GitHub Pages landing + hosted MkDocs docs. `mkdocs.yml` exists,
  but `.github/` holds only a PR template, so nothing publishes yet.

## Shipped

- [PLAN-app-lock.md](PLAN-app-lock.md) — Face ID lock + app-switcher privacy cover (#16).
- [PLAN-card-due-reminders.md](PLAN-card-due-reminders.md) — card due dates + T-3/due-day reminders (#17).
- [PLAN-pending-statement-surfacing.md](PLAN-pending-statement-surfacing.md) — Home + Accounts banners,
  reusing `StatementsEmailView` (#18). **One leftover:** `GmailManager.addPending` posts no local
  notification, so the plan's "exactly one local notification on a new pending item" criterion is unmet.
</content>
</invoke>
