# Changelog

## 0.4.0
- **Breaking:** requires Ruby 3.2 or later. Ruby 3.1 reached end of life in March 2025 and the CI runners no longer provide it
- **Breaking:** an event whose dispatch raises no longer stops the other events. `dispatch_events` dispatches them all, then raises the first error. The transaction is committed by then and nothing dispatches again, so the events left used to be lost
- **Breaking:** since the error is raised once every event is dispatched, a caller that retries the push (a Sidekiq retry) dispatches again every event that succeeded, not only the ones before the failure
- Add optional `on_dispatch_error` config: called with `(error, event)` for each dispatch error after the first, which is the one raised. Without it, those errors are written to stderr with `warn`
- `CommittingError` names the mistake: `merge_child` called from inside a db operation, with or without a block, must move to where the changeset is built

## 0.3.2
- `merge_child` with a block records a `DeferredMerge`, performed by the changeset that commits it. After an eager merge the parent has copied it in and commits it, so the child's events land in the parent, through any number of eager merges. Replaces the 0.3.1 fix, which walked back to the root of the merge chain
- `add_event`, `add_db_operation` and `merge_child` raise `AlreadyMergedError` on a changeset merged into a parent, and `AlreadyPushedError` on a pushed one: what is added afterwards would run twice or never
- `merge_child(changeset)` on itself raises `ArgumentError`; so does a `return` inside the block, instead of Ruby's bare `LocalJumpError`

## 0.3.1
- Fix: the events of a child built by a `merge_child` block reach the changeset that pushes, also when the changeset holding the block was itself merged into a parent before the push. They were added to the merged changeset's own collection, copied earlier by the parent, and never dispatched

## 0.3.0
- `merge_child` takes a block: the child is built during the commit, at the block's position in the parent's sequence, so it can read the rows the earlier operations wrote. Its db operations run there, in the same transaction; its events dispatch after the commit with the parent's. Covers what `merge_child_async` did, without a proxy
- `merge_child` raises `NotAChangesetError` when the block returns something else than a `Changeset`, and `CommittingError` when called with a changeset from inside a db operation (the child's operations would silently run last)
- **Breaking:** Remove `merge_events`, added in 0.2.2: the block form of `merge_child` replaces it

## 0.2.2
- Add `merge_events(other)`: takes over another changeset's events, to dispatch them with its own; its db operations stay the caller's business. Covers a child built inside one of the parent's db operations, without bringing back `merge_child_async`

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
