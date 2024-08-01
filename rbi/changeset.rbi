# typed: true

class Changeset
  EventPayload = T.type_alias { T.untyped }
  Callable = T.type_alias { T.any(Changeset::PersistenceInterface, T.proc.void) }
  RawEventPayload = T.type_alias { T.any(EventPayload, T.proc.returns(EventPayload)) }

  sig { params(events_catalog: ::Changeset::EventCatalogInterface).void }
  def initialize(events_catalog = Changeset::NullEventCatalog.new)
  end

  sig { params(change_set: Changeset).returns(T.self_type) }
  def merge_child(change_set)
  end

  sig { params(changeset_wrapped_in_proc: T.proc.returns(::Changeset)).returns(T.self_type) }
  def merge_child_async(&changeset_wrapped_in_proc)
  end

  sig { params(name: Symbol, raw_payload: Changeset::RawEventPayload).returns(T.self_type) }
  def add_event(name, raw_payload)
  end

  sig { params(persistence_handlers: Changeset::Callable).returns(T.self_type) }
  def add_db_operations(*persistence_handlers)
  end

  sig { params(persistence_handler: Changeset::Callable).returns(T.self_type) }
  def add_db_operation(persistence_handler)
  end

  sig { returns(T.self_type) }
  def push!
  end

  sig { params(other: Changeset).returns(T::Boolean) }
  def ==(other)
  end

  sig { returns(Changeset::Configuration) }
  def self.configuration
  end

  sig { params(block: T.proc.params(block: Changeset::Configuration).void).void }
  def self.configure(&block)
  end

  class Configuration
    DbTransactionWrapper = T.type_alias { T.proc.params(block: T.proc.void).void }

    sig { params(db_transaction_wrapper: DbTransactionWrapper).returns(DbTransactionWrapper) }
    attr_writer :db_transaction_wrapper

    sig { returns(T.proc.void) }
    def db_transaction_wrapper
    end
  end

  module EventCatalogInterface
    extend T::Helpers
    abstract!

    sig { abstract.params(event: Changeset::Event).void }
    def dispatch(event)
    end

    sig { abstract.params(event_name: Symbol).returns(T::Boolean) }
    def known_event?(event_name)
    end

    sig { returns(Class) }
    def class
    end
  end

  class AsyncChangeset
    sig { params(changeset_wrapped_in_proc: T.proc.returns(::Changeset)).void }
    def initialize(changeset_wrapped_in_proc)
    end

    sig { returns(DbOperationCollection) }
    def db_operations
    end

    sig { returns(EventCollection) }
    def events_collection
    end
  end

  class DbOperationCollection
    CollectionElement = T.type_alias { T.any(Changeset::PersistenceInterface, T.proc.void, Changeset::AsyncChangeset) }

    sig { void }
    def initialize
    end

    sig { params(persistence_handler: CollectionElement).void }
    def add(persistence_handler)
    end

    sig { params(db_operations: Changeset::DbOperationCollection).void }
    def merge_child(db_operations)
    end

    sig { params(async_change_set: Changeset::AsyncChangeset).void }
    def merge_child_async(async_change_set)
    end

    sig { params(block: T.proc.params(arg0: Changeset::Callable).returns(BasicObject)).void }
    def each(&block)
    end

    sig { params(other: Changeset::DbOperationCollection).returns(T::Boolean) }
    def ==(other)
    end

    protected

    sig { returns(T::Array[CollectionElement]) }
    attr_reader :collection
  end

  class EventCollection
    GroupedEvent = T.type_alias { T::Hash[Symbol, T::Array[Changeset::Event]] }

    sig { void }
    def initialize
    end

    sig { params(name: Symbol, raw_payload: Changeset::RawEventPayload, events_catalog: ::Changeset::EventCatalogInterface).void }
    def add(name:, raw_payload:, events_catalog:)
    end

    sig { params(event_collection: Changeset::EventCollection).void }
    def merge_child(event_collection)
    end

    sig { params(async_change_set: Changeset::AsyncChangeset).void }
    def merge_child_async(async_change_set)
    end

    sig { params(block: T.proc.params(arg0: Changeset::Event).returns(BasicObject)).void }
    def each(&block)
    end

    sig { params(other: Changeset::EventCollection).returns(T::Boolean) }
    def ==(other)
    end

    protected

    sig { returns(GroupedEvent) }
    attr_reader :grouped_events
    sig { returns(T::Array[::Changeset::AsyncChangeset]) }
    attr_reader :async_change_sets

    # only used for merge
    sig { returns(T::Array[Changeset::Event]) }
    def all_events
    end

    sig { returns(T::Array[Changeset::Event]) }
    def uniq_events
    end

    private

    sig { params(event: Changeset::Event).void }
    def add_event(event)
    end
  end

  class Event
    sig { returns(Symbol) }
    attr_reader :name

    sig { params(name: Symbol, raw_payload: Changeset::RawEventPayload, events_catalog: ::Changeset::EventCatalogInterface).void }
    def initialize(name:, raw_payload:, events_catalog:)
    end

    sig { void }
    def dispatch
    end

    sig { returns(T::Array[T.untyped]) }
    def unicity_key
    end

    sig { returns(Changeset::EventPayload) }
    def payload
    end

    sig { params(other: Changeset::Event).returns(T::Boolean) }
    def ==(other)
    end

    private

    sig { returns(Changeset::EventCatalogInterface) }
    attr_reader :events_catalog

    sig { returns(Changeset::RawEventPayload) }
    attr_reader :raw_payload
  end

  class NullEventCatalog
    include Changeset::EventCatalogInterface

    sig { override.params(event: Changeset::Event).void }
    def dispatch(event)
    end

    sig { override.params(event_name: Symbol).returns(T::Boolean) }
    def known_event?(event_name)
    end
  end

  module PersistenceInterface
    extend T::Helpers
    abstract!

    sig { abstract.void }
    def call
    end
  end

  protected
  sig { returns(Changeset::DbOperationCollection) }
  attr_reader :db_operations
  sig { returns(Changeset::EventCollection) }
  attr_reader :events_collection
  sig { returns(::Changeset::EventCatalogInterface) }
  attr_reader :events_catalog

  private

  sig { void }
  def commit_db_operations
  end

  sig { void }
  def dispatch_events
  end
end