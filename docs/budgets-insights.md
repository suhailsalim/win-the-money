# Budgets & insights

## Budget categories (`BudgetCategory`)

`{ name, symbol, spent, plan, color, isSystem }`. `spent` is recomputed from transactions
(`Store.recomputeSpent`); `plan` is the user's monthly budget. The base category set is locked and
maintained (see [transactions-and-categories.md](transactions-and-categories.md)). System categories
(`Income`, `Transfer`, `Other`) aren't user budgets but are valid classification targets.

## Plan tab (`PlanView.swift`)

Monthly budgeting: per-category planned vs spent, with `PlanMonth`/`Segment` helpers driving the
allocation visuals. Editing a category's plan updates `BudgetCategory.plan`.

## Insights tab (`InsightsView.swift`)

Analytics over transactions: spending by category and by **tag** (facet tags from the brand library, e.g.
Streaming, Quick commerce), trends over time, and top merchants. All derived live from `Store.txns` —
no extra persistence. Transfers and income are excluded from spend.
