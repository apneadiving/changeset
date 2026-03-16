# Changelog

## 0.2.1
- Add `push!(skip_transaction_check: true)` to bypass `already_in_transaction` guard when needed

## 0.2.0
- **Breaking:** Remove `merge_child_async` and `AsyncChangeset` from the gem. This was a legacy escape hatch — if you need it, monkeypatch it in your app.
- Add double-push protection: `push!` raises `AlreadyPushedError` if called twice on the same changeset
- Add merge guards: prevent pushing a merged child, merging an already-pushed or already-merged changeset
- Add optional `already_in_transaction` config: raises `AlreadyInTransactionError` if `push!` is called inside an open transaction
- Add `pushed?` and `merged?` query methods
- Simplify `EventCollection` and `DbOperationCollection` (no more async special-casing)
- `NullEventCatalog` now includes `EventCatalogInterface`
- Fix `EventCollection#uniq_events` mutating state on read
- Fix RBI return type for `Configuration#db_transaction_wrapper`
- Require Ruby >= 3.1, zeitwerk >= 2.5
- CI: drop Ruby 3.0 (EOL), add 3.3, upgrade to actions/checkout@v4

## 0.1.5
- Make `commit_db_operations` and `dispatch_events` public

## 0.1.4
- Make `DbOperationCollection` an `Enumerable`

## 0.1.3
- Add `merge_child_async` for legacy code concerns

## 0.1.2
- Breaking: `add_event` signature without keyword args

## 0.1.1
- DB operations respond to `call` instead of `commit`, opening the door to simple lambdas
- Remove constraints on event payload types
