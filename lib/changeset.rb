# typed: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

class Changeset
  def initialize(events_catalog = Changeset::NullEventCatalog.new)
    @events_collection = Changeset::EventCollection.new
    @db_operations = ::Changeset::DbOperationCollection.new
    @events_catalog = events_catalog
    @pushed = false
    @merged = false
  end

  def merge_child(child_changeset)
    raise Changeset::Errors::AlreadyPushedError, "cannot merge a changeset that has already been pushed" if child_changeset.pushed?
    raise Changeset::Errors::AlreadyMergedError, "cannot merge a changeset that has already been merged" if child_changeset.merged?

    events_collection.merge_child(child_changeset.events_collection)
    db_operations.merge_child(child_changeset.db_operations)
    child_changeset.send(:merged!)
    self
  end

  def add_event(name, raw_payload)
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
    db_operations.add(persistence_handler)
    self
  end

  def pushed?
    @pushed
  end

  def merged?
    @merged
  end

  def push!(skip_transaction_check: false)
    raise Changeset::Errors::AlreadyPushedError, "this changeset has already been pushed" if @pushed
    raise Changeset::Errors::AlreadyMergedError, "cannot push a changeset that has been merged into a parent" if @merged

    check_not_already_in_transaction! unless skip_transaction_check
    @pushed = true
    commit_db_operations
    dispatch_events
    self
  end

  def commit_db_operations
    Changeset.configuration.db_transaction_wrapper.call do
      db_operations.each(&:call)
    end
  end

  def dispatch_events
    events_collection.each do |event|
      event.dispatch
    end
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

  def merged!
    @merged = true
  end

  def check_not_already_in_transaction!
    checker = Changeset.configuration.already_in_transaction
    return unless checker
    raise Changeset::Errors::AlreadyInTransactionError, "push! called inside an open transaction" if checker.call
  end
end
