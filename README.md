[![Combo](./doc/combo.svg)](https://combohr.com)

# Changeset

A unit-of-work primitive for Rails that separates domain logic from persistence. Your services decide *what* to persist and *which events* to fire — the changeset decides *when*, in a single transaction, with events dispatched after commit.

If you're drawn to hexagonal architecture (ports and adapters) but don't want a framework, this is the minimum viable boundary: domain logic in, side effects out, one seam between the two.

> **Note on naming:** This is not related to Ecto changesets (Elixir). This gem implements a unit-of-work pattern with event dispatch.

---

<details>
<summary>Table of Contents</summary>

1. [The Problem](#the-problem)
1. [How It Works](#how-it-works)
1. [Installation](#installation)
1. [Configuration](#configuration)
1. [Usage](#usage)
   - [Events](#events)
   - [Database Operations](#database-operations)
   - [Merging Changesets](#merging-changesets)
   - [Push!](#push)
1. [Real-World Patterns](#real-world-patterns)
   - [Separating Reads from Writes](#separating-reads-from-writes)
1. [Testing](#testing)
1. [Transaction Semantics](#transaction-semantics)
1. [Sorbet](#sorbet)

</details>

## The Problem

Rails service objects tend to accumulate three issues over time:

**Interminable transactions.** Service A opens a transaction, calls service B which opens a nested transaction, which calls service C. The transaction scope becomes unknowable, and you're holding database locks far longer than necessary.

**Unpredictable callbacks.** `after_save` and `after_commit` callbacks scattered across models fire in hard-to-trace order. When workflows overlap, the same callback can trigger duplicate side effects.

**Jobs that run too early.** A background job enqueued inside a transaction can start before the transaction commits — and fail because the records don't exist yet.

The changeset solves all three by separating *what to persist* from *when to persist*, and *what side effects to trigger* from *when to trigger them*.

## How It Works

```
1. Collect DB operations       →  changeset.add_db_operation(...)
2. Collect events              →  changeset.add_event(...)
3. Compose from sub-services   →  changeset.merge_child(child_changeset)
4. Execute                     →  changeset.push!
   a. All DB operations run in a single transaction
   b. All events dispatch after the transaction commits
```

## Installation

```ruby
gem "changeset", github: "apneadiving/changeset"
```

## Configuration

Tell the gem how to wrap database transactions:

```ruby
Changeset.configure do |config|
  config.db_transaction_wrapper = ->(&block) {
    ApplicationRecord.transaction do
      block.call
    end
  }
end
```

This is the only required configuration. The gem does not force `requires_new: true` or any other transaction option — that's your choice in the wrapper.

Optionally, you can detect when `push!` is called inside an already-open transaction — which defeats the purpose of the gem:

```ruby
Changeset.configure do |config|
  config.db_transaction_wrapper = ->(&block) { ApplicationRecord.transaction { block.call } }
  config.already_in_transaction = -> { ActiveRecord::Base.connection.open_transactions > 0 }
end
```

When configured, `push!` raises `Changeset::Errors::AlreadyInTransactionError` if the check returns true. This is a no-cost check (in-memory counter, no DB call). When not configured, no check runs.

## Usage

### Events

Events trigger async processes (background jobs, AMQP, Kafka, etc.) after the transaction commits.

Events must be registered in an event catalog — any object that implements `dispatch(event)` and `known_event?(event_name)`:

```ruby
class EventsCatalog
  KNOWN_EVENTS = [:planning_updated]

  def dispatch(event)
    send(event.name, event)
  end

  def known_event?(event_name)
    KNOWN_EVENTS.include?(event_name)
  end

  private

  def planning_updated(event)
    PlanningUpdatedJob.perform_async(event.payload)
  end
end
```

Add events with a static payload (when you know all params upfront):

```ruby
changeset = Changeset.new(EventsCatalog.new)
changeset.add_event(:planning_updated, { week: "2022W47" })
```

Or with a proc payload (when the payload depends on data created during the transaction):

```ruby
changeset.add_event(:planning_updated, -> { { week: some_object.week_identifier } })
```

Proc payloads are evaluated after DB operations commit, so they can reference newly created records.

**Deduplication:** Events are deduplicated by `[event_catalog_class, event_name, payload]`. If multiple services add the same event with the same payload, it dispatches once.

### Database Operations

Any object that responds to `call` works as a DB operation:

```ruby
changeset.add_db_operation(-> { user.save! })
```

Add multiple at once:

```ruby
changeset.add_db_operations(
  -> { invoice.save! },
  -> { charge.save! }
)
```

Operations execute in the order they were added, within a single transaction.

### Merging Changesets

Changesets compose. A parent can merge any number of children:

```ruby
parent_changeset = Changeset.new(EventsCatalog.new)
parent_changeset.add_db_operation(db_operation1)

child_changeset = Changeset.new(EventsCatalog.new)
child_changeset
  .add_db_operation(db_operation2)
  .add_event(:planning_updated, { week: "2022W47" })

parent_changeset.merge_child(child_changeset)
parent_changeset.add_db_operation(db_operation3)

parent_changeset.push!
# DB operations execute in order: 1, 2, 3
# Events deduplicate and dispatch after commit
```

This is the core value: each service builds its own changeset, and the caller merges them. No service needs to know whether it's running inside a transaction or not.

### Push!

```ruby
changeset.push!
```

This does two things in sequence:
1. Runs all DB operations in a single transaction (`commit_db_operations`)
2. Dispatches all unique events outside the transaction (`dispatch_events`)

A changeset can only be pushed once. Calling `push!` a second time raises `Changeset::Errors::AlreadyPushedError`.

Both `commit_db_operations` and `dispatch_events` are public if you need to call them separately. Note: these bypass the double-push guard — they're escape hatches, not the normal path.

## Real-World Patterns

The gem is deliberately minimal — it doesn't enforce how you structure your code. Here are patterns that have emerged in production across hundreds of files.

### Services return changesets, callers push

The most common pattern: services build and return a changeset, the caller decides when to push. This keeps transaction boundaries at the edges.

```ruby
class Location::CreationService
  def initialize(account:, params:)
    @account = account
    @params = params
    @changeset = Changeset.new(Location::EventsCatalog.new)
  end

  def call
    @location = Location.new(@params)
    @changeset
      .add_db_operation(-> { @location.save! })
      .add_event(:location_created, -> { { id: @location.id } })
  end

  # Convenience method when the caller doesn't need the changeset
  def self.run!(account:, params:)
    service = new(account: account, params: params)
    service.call.push!
    service.location
  end
end

# Caller can push directly:
Location::CreationService.run!(account: account, params: params)

# Or merge into a larger workflow:
changeset.merge_child(Location::CreationService.new(account: account, params: params).call)
```

### One event catalog per domain

Each bounded context defines its own catalog. When changesets from different domains merge, each event dispatches through its own catalog:

```ruby
class Location::EventsCatalog
  KNOWN_EVENTS = [:location_created, :location_updated, :location_deleted]
  # ...
end

class Membership::EventsCatalog
  KNOWN_EVENTS = [:membership_created, :membership_changed]
  # ...
end

# A user creation service might compose both:
changeset = Changeset.new(User::EventsCatalog.new)
changeset
  .add_event(:user_created, -> { { id: user.id } })
  .merge_child(membership_service.call)   # uses Membership::EventsCatalog
  .merge_child(location_config_service.call) # uses Location::EventsCatalog
  .push!
# Each event dispatches through its own catalog
```

### Persistence classes that carry state

For complex operations, a dedicated class beats a lambda. It can encapsulate multi-step logic and expose results:

```ruby
class Shift::BulkCreate::Persistence
  include Changeset::PersistenceInterface

  def initialize(shifts:, planning:)
    @shifts = shifts
    @planning = planning
  end

  def call
    Shift.import!(@shifts)
    @planning.update!(shifts_count: @planning.shifts_count + @shifts.size)
  end
end

changeset.add_db_operation(
  Shift::BulkCreate::Persistence.new(shifts: shifts, planning: planning)
)
```

### Chaining merge_child across services

Complex workflows merge changesets from multiple services. Each service is unaware of the others:

```ruby
def appointment_attended(appointment)
  changeset = Changeset.new(Appointment::EventsCatalog.new)

  # Each service returns its own changeset with its own events
  changeset
    .merge_child(charge_service.call)
    .merge_child(insurance_claim_service.call)
    .merge_child(notification_service.call)

  changeset
end

# One transaction for all three services, events dispatched after
appointment_attended(appointment).push!
```

### Separating reads from writes

A changeset naturally pushes your services toward a clean structure: read first, build the changeset, push at the boundary. No reads happen inside the transaction, no writes happen outside it.

```ruby
class Appointment::AttendService
  def initialize(appointment:)
    @appointment = appointment
    @changeset = Changeset.new(Appointment::EventsCatalog.new)
  end

  def call
    # 1. Read phase — queries, validations, business logic (no transaction)
    charge = Charge.build_for(@appointment)
    next_slot = @appointment.location.next_available_slot
    raise "no availability" unless next_slot

    # 2. Build phase — collect what needs to happen (still no transaction)
    @changeset
      .add_db_operations(
        -> { charge.save! },
        -> { @appointment.update!(status: :attended, next_slot: next_slot) }
      )
      .add_event(:appointment_attended, -> { { id: @appointment.id, charge_id: charge.id } })

    @changeset
  end
end

# 3. Push phase — single transaction, events after commit
Appointment::AttendService.new(appointment: appointment).call.push!
```

The transaction only wraps the writes. Reads stay outside. This keeps locks short and makes the service easy to test — you can assert on the changeset without ever calling `push!`.

If you're familiar with hexagonal architecture (ports and adapters), the changeset is the boundary between your domain logic and your persistence/infrastructure layer. The read and build phases are pure domain — no side effects. The push phase is the adapter. The gem doesn't enforce this, but it makes it the path of least resistance.

## Testing

Changesets can be compared without touching the database:

```ruby
expected = Changeset.new(EventsCatalog.new)
  .add_db_operation(CreateUser.new(user))
  .add_event(:user_created, { id: 1 })

actual = my_service.call

expect(actual).to eq(expected)
```

This requires your persistence classes to implement `==`. Lambdas can't be compared for equality, so use real classes in tests.

## Transaction Semantics

- The `db_transaction_wrapper` you configure receives a block. All DB operations run inside that block. You control the transaction options (isolation level, `requires_new`, etc.).
- Events dispatch **after** the wrapper block returns — outside the transaction. This guarantees that background jobs can find the records they need.
- If any DB operation raises, the transaction rolls back and no events dispatch.
- DB operations execute in insertion order. Events deduplicate, then dispatch in insertion order.
- A changeset can only be pushed once — the second `push!` raises `AlreadyPushedError`.
- If `already_in_transaction` is configured and returns true, `push!` raises `AlreadyInTransactionError` before executing anything. You can bypass this with `push!(skip_transaction_check: true)` for cases where you intentionally push inside a transaction (e.g., inside an advisory lock that opens one).

## Sorbet

This gem is typed with Sorbet and ships with RBI definitions.

## Why a gem?

The core logic is ~100 lines — you could inline it. The value isn't the implementation, it's the shared primitive. A named abstraction that the whole team reaches for beats ten ad-hoc transaction wrappers scattered across a codebase. Without it, every developer invents their own "collect stuff, run in transaction, fire jobs after" pattern. Some use `after_commit`, some nest transactions, some enqueue jobs inside transactions. The codebase drifts. With a changeset, there's one answer: build it, push it.

This gem is intentionally small and stable. Low commit frequency reflects maturity, not abandonment. It has been running in production across hundreds of files at [Combo](https://combohr.com) since 2022.
