# Changeset

The changeset contains all database operations and events after a command is executed.

The point of the Changeset is to delay the moment you persist until the end of a chain of method calls. The main reasons are:
- use the shortest database transactions possible
- trigger necessary events once all data is persisted

Whatever the way you organize your code (plain methods, service objects...), you can leverage the changesets.


## Configuration
One configuration is need to use the gem: tell it how to use database transactions:

```ruby
Changeset.configure do |config|
  config.db_transaction_wrapper = ->(&block) {
    ApplicationRecord.transaction do
      block.call
    end
  }
end
```

## Events

They are meant to trigger only async processes:
- background jobs
- AMQP
- KAFKA
- ...

Events have to be registered in a class to be used later:

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
    # trigger worker or any async process
    # from here you can use event.payload
  end
end
```

There are two ways to add events to a changeset:
```ruby
changeset = Changeset.new(EventsCatalog)
# if you know all params at the time you add the event:
changeset.add_event(
  :planning_udpated,
  { week: "2022W47" }
)
# if you do not know all params at the time you add the event,
# but know it will be populated once database operations are committed
changeset.add_event(
  :planning_udpated,
  -> { { week: some_object.week_identifier } }
)
```

For now there is a dedup mechanism to avoid same events to be dispatched several times. Indeed some actions may add same events in their own context and afeter traversing them all we know it is not necessary.

The unicity is based on:
- the event catalog class name
- the name of the event
- the payload of the event

## Database Operations

They are meant to be objects containing the relevant logic to call the database and commit persistence operations.
These classes must match the PersistenceInterface and must respond to `commit`.

You can create any depending on your needs: create, update, delete, bulk upsert...

A very basic example is:
```ruby
class BasicPersistenceHandler
  def initialize(active_record_object)
    @active_record_object = active_record_object
  end

  def commit
    @active_record_object.save!
  end
end
```

You can then add database operations to the changeset.
```ruby
changeset = Changeset.new # notice we didnt pass an event catalog because we wont use events

user = User.new(params)

changeset.add_db_operation(
  BasicPersistenceHandler.new(user)
)
```

Database operations will then be commited in the exact order they were added to the changeset.

## Merging changesets

The very point of changesets is they can be merged. On merge:
- parent changeset concatenates all db operations of its child
- parent changeset merges all events from its child

```ruby
parent_changeset = Changeset.new(EventsCatalog)
parent_changeset
  .add_db_operations(
    db_operation1,
    db_operation2
  )
  .add_event(:planning_updated, { week: "2022W47" })

child_changeset = Changeset.new(EventsCatalog)
  .add_db_operations(
    db_operation3,
    db_operation4
  )
  .add_event(:planning_updated, { week: "2022W47" })
  .add_event(:planning_updated, { week: "2022W48" })

parent_changeset.merge_child(child_changeset)

parent_changeset
  .add_db_operation(
    db_operation5
  )

# - db operations will be in order 1, 2, 3, 4, 5
# - only one planning_updated event will be dispatched with param {week: "2022W47"}
# - only one planning_updated event will be dispatched with param {week: "2022W48"}
```

## Actually do the work

Whenever you know it is the appropriate time to persist data and trigger events, you can call:

```ruby
changeset.push!
```

This will:
- persist all database operation in a single transaction
- then trigger all events (outside the transaction)

## Testing

A very convenient aspect of using changesets in you can run multiple scenarios without touching the database.
In the end you can simply compare the actual changeset you get against your expected one

# Sorbet

This gem is compatible with Sorbet and contains all its definitions.

## Example

We need to be fault tolerant in cases like below:

```ruby
def charge(customer, amount_cents)
  # These two create! calls must
  # either both succeed or both fail
  invoice = Invoice.create!(
    customer: customer,
    amount_cents: amount_cents,
  )
  charge = Charge.create!(
    invoice: invoice,
    amount_cents: amount_cents,
  )
  ChargeJob.perform_async(charge.id)
end
```

It generally goes down to adding a transaction:

```ruby
def charge(customer, amount_cents)
  ActiveRecord::Base.transaction do
    invoice = Invoice.create!(
      customer: customer,
      amount_cents: amount_cents,
    )
    charge = Charge.create!(
      invoice: invoice,
      amount_cents: amount_cents,
    )
    # we can argue whether or not this should go inside the transaction...
    ChargeJob.perform_async(charge.id)
  end
end
```

You soon need to reuse this method in a larger context, and you now need to nest transactions:

```ruby
def appointment_attended(appointment)
  ActiveRecord::Base.transaction(requires_new: true) do
    copay_cents = appointment.service.copay_cents
    charge = charge(appointment.customer, copay_cents)

    # create_insurance_claim would create yet another nested transaction
    insurance_claim = create_insurance_claim(appointment, copay: charge)

    # again, triggering the job here is maybe not the best option
    SubmitToInsuranceJob.perform_async(insurance_claim.id)
  end
end

def charge(customer, amount_cents)
  ActiveRecord::Base.transaction(requires_new: true) do
    invoice = Invoice.create!(
      customer: customer,
      amount_cents: amount_cents,
    )
    charge = Charge.create!(
      invoice: invoice,
      amount_cents: amount_cents,
    )
    # we can argue whether or not this should go inside the transaction...
    ChargeJob.perform_async(charge.id)
  end
end
```

As you can tell, we are putting more and more weight on the transation.
Holding a transaction takes a huge toll on your database opening the door to multiple weird errors.
The most common ones being:
- timeouts
- locking errors
- background job failing because they are unable to find database records (they can actually be trigerred before the transaction ended)

---

Now with the Changeset:

```ruby
# we need a catalog
class EventsCatalog
  KNOWN_EVENTS = [:customer_charged, :insurance_claim_created]
  def dispatch(event)
    send(event.name, event)
  end

  def known_event?(event_name)
    KNOWN_EVENTS.include?(event_name)
  end

  private

  def customer_charged(event)
    ChargeJob.perform_async(event.payload[:id])
  end

  def insurance_claim_created(event)
    SubmitToInsuranceJob.perform_async(event.payload[:id])
  end
end

# we need a persistence handler
class BasicPersistenceHandler
  def initialize(active_record_object)
    @active_record_object = active_record_object
  end

  def commit
    @active_record_object.save!
  end
end

def appointment_attended(appointment)
  changeset = Changeset.new(EventsCatalog)

  copay_cents = appointment.service.copay_cents
  new_charge, charge_changeset = charge(appointment.customer, copay_cents)
  changeset.merge_child(charge_changeset)

  insurance_claim, insurance_claim_changeset = create_insurance_claim(appointment, copay: new_charge)
  changeset.merge_child(insurance_claim_changeset)

  # most methods on changeset return the changeset itself
  changeset.add_event(
    :insurance_claim_created,
    # notice the argument here is a proc: the id is not yet determined
    -> { { id: insurance_claim.id } }
  )
end

def charge(customer, amount_cents)
  changeset = Changeset.new(EventsCatalog)

  invoice = Invoice.new(
    customer: customer,
    amount_cents: amount_cents,
  )
  charge = Charge.new(
    invoice: invoice,
    amount_cents: amount_cents,
  )

  changeset
    .add_db_operations(
      BasicPersistenceHandler.new(invoice),
      BasicPersistenceHandler.new(charge)
    )
    .add_event(
      :customer_charged,
      -> { { id: charge.id } }
    )

  [charge, changeset]
end

# usage
changeset = appointment_attended(appointment)
changeset.push!
```

One database transaction, workers triggered at the apprpriate time.

## But why all these classes?

I realized this kind of structure was necessary through my job at combohr.com, where we heavily use Domain Driven Design.

Because we do not use ActiveRecord within the domain (no objects, no query, no nothing), we need a way to bridge back from our own Ruby object to the persistence layer. This is where Persistence classes came into play.

Anyway it is a good habit to have a facade to decouple your intent and the actual implementation.