# Widgets & notifications

## Home-screen widgets

| Widget | Shows |
|--------|-------|
| **Net worth** | Current liquid net worth + trend |
| **Budget** | Month's spent vs plan |
| **Goal** | Your top goal's progress |

Widgets read a local snapshot the app refreshes — they work offline and share no data.

## Siri & quick log

Say **"Log a spend in Nidhi"** (or run *Log Transaction* from the Shortcuts app) to record a cash or
UPI spend without unlocking the app — give the amount, and optionally who you paid and a category.
The spend is queued and appears the next time you open Nidhi, categorised the same way an imported
transaction would be. Running the shortcut twice never creates two copies.

The **Quick log** widget puts two or three one-tap buttons on your Home Screen, using the amounts and
categories you actually spend on most; the budget bar on the widget updates on the tap.

Siri can also answer **"How's my budget in Nidhi"** and **"What's safe to spend in Nidhi"** — but only
after you turn on *Settings → Siri & Shortcuts → Let Siri read my figures*. It's off by default
because Siri answers before the Face ID lock.

## Live Activity

The monthly-budget **Live Activity** puts spent-vs-plan and days-remaining on the Lock Screen and in
the Dynamic Island for the current month.

## Notifications

Local notifications (nothing goes through a server) can be enabled in Settings — used for import and
budget-related nudges. iOS will ask permission the first time.

## Background refresh

With Gmail connected, iOS periodically wakes the app to scan for new alert emails and statement
attachments, so numbers stay current without opening the app. iOS decides the exact schedule; opening
the app always triggers a fresh scan.
