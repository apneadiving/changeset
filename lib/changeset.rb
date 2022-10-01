# typed: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

class Changeset
  def initialize(events_catalog = Changeset::NullEventCatalog.new)
    @events_collection = Changeset::EventCollection.new
    @db_operations = []
    @events_catalog = events_catalog
  end

  def merge_child(change_set)
    events_collection.merge_child(change_set.events_collection)
    db_operations.concat(change_set.db_operations)
    self
  end

  def add_event(name:, raw_payload:)
    events_collection.add(name: name, raw_payload: raw_payload, events_catalog: events_catalog)
    self
  end

  def add_db_operations(*persistence_handlers)
    persistence_handlers.each do |persistence_handler|
      add_db_operation(persistence_handler)
    end
    self
  end

  def add_db_operation(persistence_handler)
    db_operations.push(persistence_handler)
    self
  end

  def push!
    commit_db_operations
    dispatch_events
    self
  end

  def ==(other)
    db_operations == other.db_operations &&
      events_collection == other.events_collection
  end

  def self.configuration
    @configuration ||= Changeset::Configuration.new
  end

  def self.configure(&block)
    block.call(configuration)
  end

  protected

  attr_reader :events_collection, :db_operations, :events_catalog

  private

  def commit_db_operations
    # should we move the transaction to also wrap the events?
    # in other words: should we still commit to db if events fail to dispatch?
    Changeset.configuration.db_transaction_wrapper.call do
      db_operations.each(&:commit)
    end
  end

  def dispatch_events
    events_collection.each do |event|
      event.dispatch
    end
  end
end
