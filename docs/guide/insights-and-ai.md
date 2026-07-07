# Insights & AI

## Insights tab

- **Spending breakdowns** by category over time, with month-on-month plan history.
- **International & rewards** — your foreign-currency spend grouped by currency, and card rewards
  totalled per programme (Reward Points, EDGE Miles, cashback, Scapia Coins) — all captured
  automatically from card statements.
- **Recurring transfers** — repeated payments to the same counterparty are grouped so subscriptions
  and SIPs are visible.

## AI insights (opt-in, off by default)

An optional AI summary of your month. You choose the provider:

| Provider | Where it runs |
|----------|---------------|
| Apple Intelligence | **On-device** — nothing leaves your phone |
| Ollama (local) | Your own machine |
| Anthropic / OpenAI / Gemini / OpenRouter / Azure / Ollama cloud | Their cloud, with **your** API key |

Keys are stored in the iOS Keychain.

### The privacy rule

Only an **aggregate summary** is ever sent — category totals, tag totals, goal progress, counts.
**Never** raw transactions, merchant lists, or account numbers. With Apple Intelligence or local
Ollama, even the aggregates stay on-device. If you never turn AI on, no AI code runs at all.
