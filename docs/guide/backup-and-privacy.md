# Backup, privacy & data

## Where your data lives

Everything is stored locally on your device. Secrets — Gmail tokens, statement passwords, AA
credentials, AI keys — live in the iOS **Keychain**, separate from the data itself.

## Backups

- **Auto-backup** (on by default) writes a JSON backup to the app's **Documents** folder — visible in
  the Files app and included in your normal device backup.
- With iCloud Drive available, a copy also lands there, so moving to a new iPhone restores
  automatically.
- Backups **exclude secrets** by design — after a restore, reconnect Gmail and re-enter statement
  passwords once.
- Settings shows the last-backup time; you can back up or restore on demand.

## Imported statements

Settings → **Imported statements** lists every statement ever imported. Deleting one removes exactly
the transactions it created — transactions that also arrived via alerts survive. Deleting a bank or
card removes its statements too.

## Clear all data

Settings → **Clear all data** wipes everything: data, integration state, the processed-statement
ledger, saved passwords. Backups in Files/iCloud are intentionally left alone, so you can restore
if the wipe was a mistake.

## Privacy summary

- No backend, no analytics, no tracking, no third-party SDKs.
- Network calls are limited to services you enable: Gmail (read-only), Setu AA, Yahoo/AMFI/FX quotes,
  and your chosen AI provider (aggregates only).
- The repo is open source — the claims above are verifiable in the code.
