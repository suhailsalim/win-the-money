# Execution plans

Self-contained implementation plans, written so a less capable model can execute them without
questions. Each has: goal, exact files, step order, edge cases found during exploration, and
verifiable acceptance criteria.

## Core improvements (ranked — do in order)

1. [PLAN-parser-regression-harness.md](PLAN-parser-regression-harness.md) — checked-in one-command
   parser test harness; lands the pending EMI fix. **Prerequisite for parser work.**
2. [PLAN-backup-rotation-and-safety.md](PLAN-backup-rotation-and-safety.md) — rotating backups,
   overwrite sanity gate, restore preview.
3. [PLAN-pending-statement-surfacing.md](PLAN-pending-statement-surfacing.md) — surface locked
   statements waiting for a password.
4. [PLAN-plan-period-cap-snapshots.md](PLAN-plan-period-cap-snapshots.md) — truthful historical
   budget caps.
5. [PLAN-axis-scapia-per-txn-rewards.md](PLAN-axis-scapia-per-txn-rewards.md) — EDGE Miles per-txn
   parsing (needs #1).

## Missing features (ranked)

1. [PLAN-app-lock.md](PLAN-app-lock.md) — Face ID lock + app-switcher privacy
2. [PLAN-card-due-reminders.md](PLAN-card-due-reminders.md) — card due dates + payment reminders
3. [PLAN-subscription-reminders.md](PLAN-subscription-reminders.md) — recurring-charge prediction
4. [PLAN-global-search.md](PLAN-global-search.md) — transaction search & filters
5. [PLAN-txn-export.md](PLAN-txn-export.md) — CSV/JSON export
6. [PLAN-cashflow-forecast.md](PLAN-cashflow-forecast.md) — safe-to-spend projection (after 2 & 3)
7. [PLAN-loans-emi-tracking.md](PLAN-loans-emi-tracking.md) — loans as liabilities
8. [PLAN-monthly-report.md](PLAN-monthly-report.md) — shareable month-in-review
9. [PLAN-app-intents-quick-log.md](PLAN-app-intents-quick-log.md) — Siri/Shortcuts quick logging
10. [PLAN-cloudkit-sync.md](PLAN-cloudkit-sync.md) — multi-device sync (needs paid dev team; do last)

## Web

- [PLAN-website.md](PLAN-website.md) — GitHub Pages landing + hosted MkDocs docs
