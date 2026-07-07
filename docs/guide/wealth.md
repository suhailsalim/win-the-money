# Wealth & investments

## Net worth

**Liquid net worth = banks + deposits + investments** (card outstandings reduce it). It's sampled once
a day to draw the trend charts on Home and Wealth, and drives the milestone ladder.

## Investments

Track **stocks, ETFs, and mutual funds** with units and average cost. Prices refresh live:

- **Stocks & ETFs** — Yahoo Finance (Indian symbols like `RELIANCE.NS` work as-is).
- **Mutual funds** — official AMFI NAVs, matched by scheme.
- No API keys, no accounts — free public endpoints, fetched directly from your device.

Buying more of an existing holding averages your cost automatically. Each holding shows invested,
current value, and P&L (₹ and %). Until a price loads, value falls back to cost basis rather than zero.

Non-INR holdings and income convert at live FX rates.

## Composition

The Wealth tab breaks net worth down by asset class — how much sits in banks vs deposits vs equity —
next to the milestone ladder.

## Deposits

FDs and RDs (imported from combined statements or added manually) appear here with their value counted
into net worth, and can back goals.
