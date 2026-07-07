# Accounts, cards & deposits

## Bank accounts

Each account shows its name, bank, masked number (last 4 digits), and a live balance. Accounts are
created automatically by statement import, Gmail alerts, or AA sync — or manually.

### How the balance stays right

The displayed balance is **reconstructed, not stored**: the app keeps the last authoritative reading
(a statement closing balance, a bank "available balance" email, or your manual edit) as an *anchor*,
then adds every transaction dated after it. This means:

- An old statement can never overwrite a newer balance.
- A missed or duplicate transaction can't permanently corrupt the figure — the next anchor heals it.
- Editing the balance by hand sets a new anchor "as of now".

## Credit cards

Cards track outstanding amount, credit limit, and available limit, populated from card statements.
If a card shows **limit ₹0**, it was created from a spend alert before any statement was imported —
import the card's statement and the limit fills in.

Card statements also capture, per transaction:

- **Rewards** — HDFC Reward Points, Axis EDGE Miles, ICICI cashback, Scapia Coins (shown as a star chip).
- **International spend** — the original currency and amount (shown as a globe chip), tagged
  "International" for the Insights breakdown.

## Deposits (FD / RD)

Fixed and recurring deposits are parsed out of combined bank statements automatically (or added
manually) and counted in net worth. They can also back a goal — see [Goals](goals.md).

## Viewing transactions per account

Every bank and card row has a **view transactions** button (and context-menu item) that opens the
transaction list pre-filtered to that account.

## Deleting an account

Deleting a bank or card also removes its imported statements and the transactions that came from them
(see [Backup, privacy & data](backup-and-privacy.md#imported-statements)).
