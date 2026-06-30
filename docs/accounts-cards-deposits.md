# Accounts, cards & deposits

## Bank accounts (`BankAccount`)

Name, type, mask (last 4), balance, optional bankCode/IFSC/branch/tier, colour/image. Created/updated by
statement import, Gmail balance alerts, AA sync, or manually in `AccountsView`/`Sheets.swift`. Upserted by
`mask`; `dedupeAccountNames` appends `••mask` when names collide.

### Balance anchors (iron-clad reconstruction)

The displayed `balance` is **derived, never blindly overwritten**. Each account also stores a balance
**anchor** — `balanceAnchor` (the last authoritative reading) and `balanceAsOf` (when it was true,
end-of-day). The live figure is always `balanceAnchor + Σ(txn.amount for txns dated after balanceAsOf)`,
computed by `Store.derivedBalance` / `recomputeBankBalances` (idempotent; runs on every txn change via
`recomputeSpent`).

- **Sources of an anchor:** HDFC-style "available balance" emails (`applyBalances` →
  `BalanceUpdate{mask, balance, asOf}`, parsed from the email's `as of <date>`), statement closings
  (`upsertAccount`, `SyncedAccount.asOf`), and manual edits (anchored to *now*).
- **Newest reading wins:** `setBalanceAnchor` only advances the anchor **forward in time**, and
  `applyBalances` keeps just the newest reading per `mask`. So Gmail's newest-first fetch order (or a
  rescan of older daily emails) can't let a stale value win, and an old statement can't clobber a newer
  alert. `nil` anchor ⇒ legacy/manual behaviour (balance used verbatim; un-anchored live feeds still
  run a running balance in `mergeSynced`).
- **Self-healing:** because the figure is a pure function of `(anchor, later txns)`, a missed or
  duplicated transaction no longer corrupts a stored running total — the next correct anchor (a daily
  email) or recompute fixes it, and a recent anchor keeps the reconstruction window tiny.

## Credit cards (`CreditCard`)

Name, mask, outstanding, limit, optional bankCode/network/tier/colour/image, optional reward balance.
Statement import fills outstanding + limit (`CardStatementParser` per issuer; an available-limit
fallback derives `total = available + outstanding` when the printed total label is missing). `limit`
defaults to `0` when unknown — a `0` on an imported card means no statement has reached it yet
(re-import to populate), since cards auto-created from spend-alerts start at `0`. Covers are
**app-generated gradients** (or a user image) — no issuer artwork is bundled.

## Catalogs

- `BankCatalog.swift` — banks (code, name, IFSC prefix, colours); `match(ifsc:)`, `info(code)`.
- `CardCatalog.swift` — factual Indian card products (`CardInfo{bankCode,name,network,tier,gradient}`,
  `id = bankCode·name·network` so same-named Visa/RuPay variants stay distinct). `cards(for:)`,
  `gradient(...)`, `networkGradient(...)`.

The Add-card sheet picker binds to its own `selectedProduct` state (not the card's display name) so the
selection always matches a tag; choosing a product fills name/network/tier/cover.

## Deposits (`Deposit`)

Fixed (FD) and recurring (RD) deposits: bank, tag (FD/RD), rate, current value, start/maturity dates, and
an optional `identifier` (the deposit account number) used to **upsert on re-import** (`mergeDeposits`).
Combined HDFC statements parse FDs/RDs automatically; deposits count toward net worth and show under Wealth.
