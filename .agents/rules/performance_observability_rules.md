# Performance, Concurrency & Observability Rules

These rules govern transfer concurrency, memory budgets during chunking/compression, and state observability across background services in TelStorage.

---

## 1. Concurrency Ceilings & Transfer Limits

- **Bounded Parallelism**: Enforce a strict ceiling on simultaneous transfers (uploads + downloads combined, default maximum 3–4 concurrent workers).
- **Prevent Network Choking & UI Freezes**: Unbounded parallel transfers cause socket starvation, high CPU jitter, and background service ANRs on mobile devices.
- **Fair Queue Scheduling**: Transfers must be scheduled sequentially through `TransferQueueService` and `DownloadQueueService` rather than spawned as unbounded ad-hoc futures.

---

## 2. Memory Ceilings: Streaming over Buffering

- **Streaming Pipelines**: For chunked uploads, downloads, and ZIP archive creation, stream data chunk-by-chunk using `Stream<List<int>>` and `ChunkInputStream` rather than loading entire multi-megabyte/gigabyte files into RAM (`Uint8List`).
- **Memory Ceiling Guard**: Any pipeline dealing with media or archives must have a defined RAM ceiling (e.g. max single chunk in memory $\le 20\text{ MB}$).
- **Regression Check on Pipeline Changes**: When modifying chunking or ZIP algorithms, verify that memory consumption does not scale linearly with file size.

---

## 3. Background Queue Observability & State Inspection

- **Inspectable State**: Every background service and queue worker (`SyncQueueService`, `TransferQueueService`, `ForegroundService`) must maintain inspectable state:
  - Active task ID and name
  - Current processing stage (e.g. `'Chunk 3/10'`, `'Compressing'`, `'Uploading'`)
  - Last encountered error message and timestamp
  - Last successfully completed milestone
- **Diagnostic Transparency**: Ensure state can be viewed via debug logs or a diagnostics panel without having to attach a live debugger or reproduce complex timing races.
