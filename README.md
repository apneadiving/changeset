# Changeset

The point of the changeset is to contain all database operations and events after a command is executed.

The logic behind it is to NOT touch database or sidekiq during the command phase as shown in the folling diagram:

![Changeset logic](./doc/changeset.png)

## Database operations

They are meant to be objects containing the relevant logic to call the database and commit persistence operations. These classes must match the PersistenceInterface.

This means you have to create a class for each database operation you actually use: create, update, delete, bulk upsert...

A very important responsibility of these classes is to add back the database id to the domain objects (basically on creation), because some other domain objects may need the relationship.

## Events

They are meant to trigger only async processes, for the time being: trigger workers.

## Architecture

When using changeset, a few steps (and objects) are expected:
- DO NOT use ActiveRecord object withing the domain -> convert AR objects to domain objects (DTOs)
- commands from the domain expect arguments. Ideally create a dedicated class to pass all arguments at once as CommandInput
- commands return an output (potentially in form of a dedicated object if relevant) and their changeset
- commands can call subcommands and merge their changeset
- outside the domain, the changeset can be pushed to get database operations done and events broadcasted
