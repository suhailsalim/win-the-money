# Goals, income, tax & net worth

## Net worth

`Store.liquidNetWorth = banks + deposits + investments` (cards/outstanding reduce it as applicable).
`nwHistory` samples net worth once per day (`wtm_nw_day`) to drive the Wealth/Home trend charts.
`netWorthTarget` and `milestones` track progress (see [gamification.md](gamification.md)).

## Goals (`Goal` / `GoalStatus`)

`{ title, symbol, saved, target, monthly, deadline, status(.onTrack/...) }`. `GoalsView.swift` shows
progress, required monthly contribution, and on-track status. Pure local state on `Store.goals`.

## Income (`IncomeStream`) — `IncomeView.swift`

`{ name, symbol, annual, currency, monthly, accountId, creditDay }`. Income streams feed expected monthly
inflow and can be linked to an account + a credit day. Non-INR streams convert via `FXProvider`.

## Tax

A lightweight India income-tax estimate on `Store` (`deductions`, `taxTotal`, `advanceTaxPaidStages`) —
an indicative figure for planning, surfaced in the Income tab. **Not** tax advice; verify independently.
