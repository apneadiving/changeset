# 0.1.4
- Make DbOperationCollection an enumerable

# 0.1.3
- Add `merge_child_async` for legacy code concerns

# 0.1.2
- Breaking change: `add_event` signature without keyword args

# 0.1.1
- Now Db operations have to respond to `call` vs `commit`, opening the doors to simple lambdas.
- Remove constraints on events payload types
