# Troubleshooting

## "My balance looks wrong / stale"

1. Check Settings → **Needs password** — a locked statement may be waiting; unlock it once and the
   password is remembered.
2. Balances are anchor + later transactions. Import the latest statement (or let a daily balance email
   arrive) to set a fresh anchor — it self-heals.
3. As a last resort, edit the balance manually; that sets a new anchor "as of now".

## "My credit card shows limit ₹0"

The card was created from a spend alert; import any statement for that card and the limit populates.

## "A statement imported the account but no transactions"

Deliberate: that statement's internals didn't reconcile against its own closing balance, so the app
refused to guess amounts. The balance is still right; Gmail alerts usually fill in the transactions.

## "The same transaction appears twice"

Shouldn't happen across alert + statement (they merge within a 4-day window). If two rows really are
one purchase (e.g. very delayed settlement), delete one — re-imports won't bring it back, imports are
idempotent.

## "A transaction has the wrong category"

Re-categorise it — the app learns that merchant permanently. Settings → **Re-scan categories** re-runs
the library on old data without touching your manual choices.

## "Transactions tagged *Needs review*"

The statement line was ambiguous (bad print, unreadable date). Settings → **Conflicts to review** shows
each with the original statement text; edit the transaction to resolve.

## "Gmail import stopped"

Reconnect Gmail in Settings (tokens can expire if revoked from your Google account). The processed
ledger ensures reconnecting never duplicates old imports.

## Console noise (developers)

`nw_protocol_… udp`, `CoreGraphics PDF has logged an error`, `<decode: bad range …>` are harmless
OS/PDFKit logs — not app bugs.
