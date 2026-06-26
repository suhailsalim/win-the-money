# Gamification

Light, optional motivation layer — all local, no leaderboards or network.

## XP & levels

`Store` tracks XP and derives a level + level name from it. XP accrues from positive money habits
(reaching milestones, saving toward goals, etc.). Shown on the profile/home surfaces.

## Milestones (`Milestone`)

Net-worth checkpoints `{ amount, name, tag, reached, active, pct }`. `Store.refreshMilestones` marks the
active milestone and progress (`pct`) as `liquidNetWorth` grows; `defaultMilestones()` seeds the ladder.

## Badges (`Badge`)

`{ symbol, label, earned }` achievements seeded by `defaultBadges()` and flipped to `earned` when their
condition is met. Purely cosmetic recognition.

These exist to make consistent tracking rewarding; none of them affect financial calculations.
