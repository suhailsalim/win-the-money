# Integrations

All integrations are opt-in and run on-device. Secrets live in the Keychain (`Keychain.swift`).

## Gmail (read-only) — `GmailManager.swift`, `GmailProvider.swift`, `GmailBackground.swift`

- OAuth 2.0 + **PKCE**, scope `gmail.readonly`. Public iOS client id from `Info.plist` (`GIDClientID`);
  no client secret. The web step uses `ASWebAuthenticationSession` (anchor: `wtmPresentationAnchor()`).
  Tokens are stored in the Keychain.
- **Two scans**: transaction-alert emails (`EmailTransactionParser.swift`) and statement-PDF attachments
  (routed through `StatementImporter`). Background refresh via `BGTask` (`…gmailrefresh`, `…stmtrefresh`).
- **Processed-statement ledger**: handled statement keys (`messageId:attachmentId`) persist in
  `gmail_done_stmts`; a scan skips anything already in `pending` **or** `processed`, marks success/dismiss
  as processed, and de-dups `pending` on load. This prevents duplicate re-imports and pending pile-up.
  `importPending` (user enters a PDF password) imports, vaults the password, and marks processed.
  "Clear all data" clears the ledger.

## Account Aggregator (Setu) — `BankSync.swift`, `SetuAAClient.swift`, `SyncManager.swift`, `BankSyncUI.swift`

- **Off by default** (`accountAggregatorEnabled`). When enabled, connects banks via Setu AA with a consent
  web step; `SetuAAClient` calls the API with `x-client-id`/`x-client-secret` (entered in Settings, stored
  in Keychain). `RebitFI.parse` reads the ReBIT-standard FI JSON defensively into `SyncedAccount`/`SyncedTxn`.
- A mock/no-network path exists for development.

## Market data

- `QuoteProvider.swift` — Yahoo Finance (stocks/ETFs) + AMFI (mutual fund NAV). See [investments.md](investments.md).
- `FXProvider.swift` — currency rates from a public endpoint (`Store.fxRates`).

## Device

- `Notifications.swift` — local notifications (`notificationsEnabled`).
- `LiveActivity.swift` + `WinTheMoneyWidgets/` — widgets / Live Activity surfaces.
- `WinTheMoneyApp.swift` — registers BG tasks and injects `Store`.
