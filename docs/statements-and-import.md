# Statements & import

On-device parsing of bank/card statement PDFs (and CSV/spreadsheets) into accounts + transactions
(+ deposits). No data leaves the device.

## Pipeline

```
StatementImporter.parse(url|data, password)  ->  ImportResult { accounts, txns, deposits }
        │  unlocks PDF (password) ─ text layer? ─┐
        │                                        ├─ isCombinedHDFC → StatementParser.parseCombined
        │                                        ├─ CardStatementParser.parse (card?)
        │                                        └─ StatementParser.parse + .account (single bank)
        └─ no text layer → Vision OCR → text parse
Store.mergeImport(ImportResult)  ->  upsert accounts/cards, dedup txns, upsert deposits
```

Key files: `StatementImporter.swift` (routing + OCR), `StatementParsers.swift` (bank statements:
HDFC, Federal, combined), `CardStatementParser.swift` (credit-card statements), `PDFTableReader.swift`
(glyph→word coordinate reconstruction), `SpreadsheetImporter.swift` (CSV/TSV/XLSX), `BankSync.swift`
(the `ImportResult`/`SyncedAccount`/`SyncedTxn` DTOs), `StatementVault.swift` (Keychain password vault).

## Parser strategy

- **Coordinate reconstruction**: `PDFTableReader.words(doc)` returns per-page `[PDFWord]{text,x,y,w}`;
  parsers cluster words into rows by `y` and columns by `x` to recover date/narration/amount/balance.
- **Text-layer fallback / balance chain**: some statements (HDFC combined, the newer Federal eStatement)
  have **fragmented or mispositioned glyph coordinates**. There, the parser uses the **text layer** and
  signs each amount by the **running-balance delta**, then **reconciles** the reconstructed closing to a
  stated closing balance — if it doesn't reconcile, it imports the account/balance but **skips txns**
  rather than emit wrong amounts (Gmail alerts cover those).
- **Account identity**: `StatementParser.account(text)` extracts mask, type, IFSC, branch, tier and the
  balance (`Available`/`Closing Balance`). Returned even when the txn table is empty/sparse.
- **Combined HDFC**: `isCombinedHDFC` + `parseCombined` split multiple savings/current accounts and parse
  FDs/RDs into `Deposit`s (deduped by `identifier`).

## Idempotency / dedup

- Transactions dedup by stable `externalId` (e.g. `fed:<tranId>:<bal>`, `hdfc:…`, `cc:…`).
- Accounts upsert by `mask`; deposits upsert by `identifier`.
- Gmail re-scans are gated by a processed-statement ledger (see [integrations.md](integrations.md)).
- A statement's closing balance becomes a dated **balance anchor** (`SyncedAccount.asOf`), not a raw
  overwrite — the live balance is then derived as `anchor + Σ(later txns)` and only the newest reading
  per account wins, so an old statement never clobbers a newer Gmail "available balance" alert. See
  [accounts-cards-deposits.md](accounts-cards-deposits.md#balance-anchors-iron-clad-reconstruction).

## Adding a new bank/card parser

1. Dump the statement to inspect layout: a tiny Swift+PDFKit script printing `page.string` and
   `PDFTableReader.words` (text + x/y). (No poppler/`pdftotext` in this env.)
2. Add a branch/parser in `StatementParsers.swift` (bank) or `CardStatementParser.swift` (card),
   following the coordinate-or-balance-chain pattern above. Produce `SyncedTxn`s with a stable
   `externalId` and a clean `merchant`.
3. **Verify with the offline harness:** copy the parser file(s) + `PDFTableReader.swift` + stub
   `SyncedTxn/SyncedAccount/Deposit` types + a `main.swift` that loads the real PDF, then
   `swiftc -O *.swift && ./a.out`. Assert account fields, txn count, signs, and that the final balance
   reconciles. Never commit real statements or numbers.
