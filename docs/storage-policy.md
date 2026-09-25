# Storage policy

## Current decision

The current release keeps the existing schema-v2 single-JSON `SharedPreferences` backend for compatibility. This is an MVP storage choice, not an unbounded long-term database design.

No retention policy is enabled. The app must not silently truncate, age out, archive, or delete user events or improvements to stay below a storage limit.

## Capacity guard

The encoded schema-v2 payload is measured in UTF-8 bytes before every write.

- migration review threshold: 4 MiB
- hard write ceiling: 8 MiB

The 4 MiB threshold is an engineering signal for starting the structured-storage migration before the hard limit becomes user-visible. It does not remove data or block reads.

If a mutation would make the payload larger than 8 MiB, the write fails closed before `SharedPreferences.setString` is called. The previously persisted payload remains authoritative and unchanged. The UI receives a storage error and can direct the user to export their data instead of silently losing history.

Existing payloads are still readable even if they are already above the limit. The limit applies to the next mutation, not to startup, so an upgrade cannot strand an existing user by refusing to load their history.

## Expected usage and performance check

For capacity planning, use 10 friction events per day for three years as an intentionally conservative reference: roughly 10,950 events, plus improvements. `tool/storage_benchmark.dart` exercises 1,000, 5,000, and 10,000 deterministic events and reports encoded bytes plus encode/decode elapsed time.

Run:

```bash
dart run tool/storage_benchmark.dart
```

The benchmark is diagnostic rather than a fixed CI timing gate because wall-clock values vary substantially by host. A regression is actionable when either of these becomes true on representative Android hardware or CI comparison runs:

1. the 10,000-event payload approaches the 4 MiB migration-review threshold, or
2. load/save serialization produces visible UI latency or materially regresses from the established baseline.

Do not raise the 8 MiB ceiling merely to suppress a capacity failure without re-evaluating storage architecture.

## SQLite migration trigger

Move to structured local storage when the soft threshold or measured interaction latency makes the single-JSON backend unsuitable. SQLite is the preferred next step because events and improvements are naturally record-oriented and future search, aggregation, backup, and incremental writes benefit from indexed rows and transactions.

A migration must be developed as a separate compatibility change. It must include:

- one-way import from the current schema-v2 JSON payload;
- deterministic event/improvement count and field parity checks;
- transaction rollback on any parse/write/parity failure;
- preservation of the original SharedPreferences payload as a rollback copy until the new store has been reopened and verified;
- no automatic deletion of that rollback copy in the same release that first migrates data;
- an explicit later cleanup policy and user impact review before old data is removed.

The application must never treat a partially migrated database as success.

## Retention and deletion

There is currently no automatic retention. User-initiated deletion keeps its existing product semantics. Introducing archival, logical deletion, snapshots, or retention changes is a separate product/data-lifecycle decision and must not be inferred from this capacity guard.
