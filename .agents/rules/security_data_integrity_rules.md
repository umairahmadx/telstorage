# Security, Data Integrity & Telegram Architecture Rules

These rules govern security hygiene, sensitive credential management, Telegram backend failure modes, and long-term data integrity in TelStorage.

---

## 1. Zero Secret Logging & Sanitized Telemetry

- **Never Log Sensitive Content**: Never output bot tokens, API keys, session strings, authentication hashes, or raw file binary payloads to `AppLogger`, `print()`, or console logs.
- **Log Metadata Only**: Telemetry and logs must only contain sanitized identifiers (e.g. `fileId`, `chunkIndex`, `mimeType`, `sizeMb`, `taskId`).

---

## 2. Credential Protection & `.gitignore` Coverage

- **No Committed Secrets**: Never hardcode or commit bot tokens, API credentials, or local environment files.
- **Gitignore Audits**: Verify `.gitignore` explicitly covers all local config files, environment definitions, and keystores.

---

## 3. Telegram-As-Storage Backend Failure Modes

Because TelStorage uses Telegram messages as a distributed storage backend, the transfer pipeline must explicitly handle these named failure modes:

- **Bot Token Revocation**: If Telegram API returns `401 Unauthorized` or token invalidation, halt the queue, notify the user with an auth banner, and avoid infinite retry storms.
- **Rate-Limiting (429 / FloodWait)**: When hitting `FLOOD_WAIT_X` from Telegram, pause the specific worker for the requested duration ($X$ seconds) and back off gracefully rather than failing tasks immediately.
- **Deleted Messages / Expired File IDs**: When fetching chunks, handle missing messages (`MESSAGE_ID_INVALID`) as permanent failures and surface clear diagnostics rather than crashing the decoder.

---

## 4. Chunk Manifest Integrity & Verification

- **Chunked Storage Architecture**: Files split across multiple Telegram message chunks rely on an accurate manifest.
- **Periodic / On-Demand Verification**: Implement an integrity pass capable of validating a file's chunk manifest against what is retrievable from Telegram to detect silent chunk loss before a user initiates a full download.
- **Digest Validation**: Validate SHA-256 hash checksums on reassembled files against the manifest digest upon download completion.
