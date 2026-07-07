# Transactions & categories

## Where transactions come from

Statement PDFs, Gmail alert emails, Account Aggregator sync, spreadsheet import, and manual entry.
All sources are de-duplicated: the same purchase seen in an alert *and* a statement becomes one
transaction (the statement's richer details win, and the row is marked statement-confirmed).

## Automatic categorisation

Every incoming transaction is classified in this order:

1. **Transfers** — credit-card bill payments and self-transfers are excluded from spending.
2. **Refunds** — credits with refund keywords get a *Refund* tag.
3. **Income** — other credits.
4. **Your rules** — if you've ever re-categorised this merchant, your choice wins forever.
5. **Brand library** — a built-in merchant catalog (Swiggy → Food, Netflix → Subscriptions, …)
   that also adds facet tags.
6. **Keyword fallback** — otherwise *Other*.

### Teaching it

Re-categorise any transaction and the app remembers the merchant→category rule. Settings →
**Re-scan categories** re-runs the library over old transactions — it never overrides your manual rules.

## Tags

Transactions can carry tags — some automatic (*International*, *Refund*, *Needs review*), plus your
own. Tags are filterable in transaction lists.

## Logging manually

The log sheet captures merchant, amount, category, account, date — and an optional "Statement details"
section (rewards, forex) if you want manual entries to match imported ones.

## Needs review

When a statement's print quality forces the parser to guess (an unreadable date, an ambiguous amount),
the transaction is imported but flagged **Needs review** and listed under Settings →
**Conflicts to review**, linked to the exact statement line it came from. Edit the transaction (or
swipe the conflict away) to resolve it. The app never silently stamps "today" on an unparseable date.
