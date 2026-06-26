# Accounts, cards & deposits

## Bank accounts (`BankAccount`)

Name, type, mask (last 4), balance, optional bankCode/IFSC/branch/tier, colour/image. Created/updated by
statement import, Gmail balance alerts, AA sync, or manually in `AccountsView`/`Sheets.swift`. Upserted by
`mask`; `dedupeAccountNames` appends `••mask` when names collide. Balances can be set authoritatively via
`Store.applyBalances` (e.g. HDFC "available balance" emails).

## Credit cards (`CreditCard`)

Name, mask, outstanding, limit, optional bankCode/network/tier/colour/image, optional reward balance.
Statement import fills outstanding + limit. Covers are **app-generated gradients** (or a user image) —
no issuer artwork is bundled.

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
