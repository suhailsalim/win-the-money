# Investments

## Model

`Investment { name, kind, units, avgCost, identifier, lastPrice, lastUpdated }` where
`InvestmentKind = .stock | .etf | .mutualFund`. Derived: `invested = units·avgCost`,
`currentValue = units · (lastPrice > 0 ? lastPrice : avgCost)` (falls back to cost basis until a price
loads), `pnl`, `pnlPct`.

## Quotes — `QuoteProvider.swift` (free, no API keys)

- **Stocks & ETFs**: Yahoo Finance — search `query2.finance.yahoo.com/v1/finance/search`, price
  `query1…/v8/finance/chart/<SYMBOL>`. The full Yahoo symbol (incl. suffix like `.NS`/`.BO`) is used as-is.
- **Mutual funds**: AMFI NAV list (matched by scheme code/name).
- `search(_:kind:market:)` filters by exchange + `quoteType`. Note Yahoo tags **Indian** ETFs as `EQUITY`
  but **US** ETFs as `ETF`, so the ETF filter accepts both. `refresh()` prices everything except MFs via
  Yahoo and MFs via AMFI.

## Markets — `MarketCatalog.swift`

`Market { country, exchange, suffix, codes, currency }` for the add flow: pick **country → exchange →
search**. Covers NSE/BSE (India), NASDAQ/NYSE (US), LSE, TSX, XETRA, TSE, HKEX, SGX, ASX. `default` is
India · NSE.

## Add / edit flow (`AddInvestmentSheet` in `Sheets.swift`)

- **No "current price" field** — price/NAV auto-loads from the API after save via
  `Task { await store.refreshQuotes() }` (a picked search hit also seeds the price immediately).
- **Buy more (edit mode)**: enter units bought + buy price → `applyBuyMore()` weighted-averages into the
  holding: `avgCost = (units·avg + add·price) / (units + add)`, `units += add`. No manual average edits.

FX for non-INR holdings/currencies comes from `FXProvider.swift`.
