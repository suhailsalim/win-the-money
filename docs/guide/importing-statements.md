# Importing statements

## Supported formats

- **Bank statement PDFs** — HDFC, Federal Bank, and HDFC *combined* statements (multiple savings/current
  accounts + FDs/RDs in one PDF, all extracted).
- **Credit-card statement PDFs** — HDFC (incl. Diners), Axis (incl. Atlas), ICICI (Amazon Pay), Scapia
  (Federal).
- **Spreadsheets** — CSV / TSV / XLSX exports.
- Scanned/image-only PDFs fall back to on-device OCR.

Everything is parsed **on your device** — the PDF never leaves your phone.

## Password-protected PDFs

Most Indian bank statements are password-locked (typically a formula like the first 4 letters of your
name + DDMM of birth). Enter the password once and it's stored in the iOS Keychain; every future
statement from that bank unlocks automatically — including ones arriving via Gmail.

A statement that arrives locked with no known password waits in Settings → **Needs password** rather
than being lost. Until you unlock it, its account/transactions are missing — check this list if a
number looks low.

## What an import gives you

- The **account or card** itself (created even from a sparse statement), with mask, type, IFSC/branch,
  credit limit.
- **Transactions** with clean merchant names, correct dates, rewards and forex details.
- **Deposits** (FDs/RDs) from combined statements.
- A **balance anchor** — the statement's closing balance, dated, feeding the reconstructed live balance.

## Accuracy over completeness

Some statements (HDFC combined, newer Federal eStatements) have deliberately scrambled internals. The
parser reconstructs them and **reconciles the result against the statement's own closing balance** —
if the maths doesn't check out, it imports the account and balance but *skips* the transactions rather
than import wrong amounts. Gmail alerts usually cover the gap.

## Re-importing is safe

Imports are idempotent: re-importing the same statement never duplicates transactions or accounts.
Each import is also recorded in Settings → **Imported statements**, where you can delete a statement
and cascade-remove exactly the transactions it created (alert-sourced ones stay).
