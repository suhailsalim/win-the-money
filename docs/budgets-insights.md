# Budgets & insights

## Budget categories (`BudgetCategory`)

`{ name, symbol, spent, plan, color, isSystem, period, customMonths, anchor }`. `plan` is the cap **per
its cycle** (`period`: monthly / quarterly / annual / custom); `spent` is recomputed by
`Store.recomputeSpent` over that category's *current* cycle window (`Store.cycleWindow`) — so a yearly
insurance cap tallies the whole year. The monthly overview folds non-monthly caps in at their per-month
equivalent (`BudgetCategory.monthlyPlan`), so `Store.planTotal` stays coherent. Monthly/quarterly align
to the calendar; annual/custom step from the category `anchor` (e.g. a renewal date) or the FY start.
The base category set is locked and maintained; system categories (`Income`, `Transfer`, `Other`) aren't
user budgets but are valid classification targets.

## Plan tab (`PlanView.swift`)

Monthly budgeting: per-category planned vs spent, with `PlanMonth`/`Segment` helpers driving the
allocation visuals. Editing a category's plan updates `BudgetCategory.plan`.

## Insights tab (`InsightsView.swift`)

Analytics over transactions: spending by category and by **tag** (facet tags from the brand library, e.g.
Streaming, Quick commerce), trends over time, and top merchants. All derived live from `Store.txns` —
no extra persistence. Transfers and income are excluded from spend.
