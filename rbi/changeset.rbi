# typed: true

class Changeset
  EventPayload = T.type_alias { T.untyped }
  Callable = T.type_alias { T.any(Changeset::PersistenceInterface, T.proc.void, Changeset::DeferredMerge) }
  RawEventPayload = T.type_alias { T.any(EventPayload, T.proc.returns(EventPayload)) }

  sig { params(events_catalog: ::Changeset::EventCatalogInterface).void }
  def initialize(events_catalog = Changeset::NullEventCatalog.new)
  end

  sig { returns(T::Boolean) }
  def pushed?
  end

  sig { returns(T::Boolean) }
  def merged?
  end

  sig { params(child_changeset: T.nilable(Changeset), build_child: T.nilable(T.proc.returns(Changeset))).returns(T.self_type) }
  def merge_child(child_changeset = nil, &build_child)
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

  sig { params(skip_transaction_check: T::Boolean).returns(T.self_type) }
  def push!(skip_transaction_check: false)
  end

  sig { void }
  def commit_db_operations
  end

  sig { void }
  def dispatch_events
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
    DbTransactionWrapper = T.type_alias { T.untyped }
    TransactionChecker = T.type_alias { T.proc.returns(T::Boolean) }

    sig { params(db_transaction_wrapper: DbTransactionWrapper).returns(DbTransactionWrapper) }
    attr_writer :db_transaction_wrapper

    sig { params(already_in_transaction: TransactionChecker).returns(TransactionChecker) }
    attr_writer :already_in_transaction

    sig { returns(DbTransactionWrapper) }
    def db_transaction_wrapper
    end

    sig { returns(T.nilable(TransactionChecker)) }
    def already_in_transaction
    end

    DispatchErrorReporter = T.type_alias { T.proc.params(error: StandardError, event: Changeset::Event).void }

    sig { params(on_dispatch_error: T.nilable(DispatchErrorReporter)).returns(T.nilable(DispatchErrorReporter)) }
    attr_writer :on_dispatch_error

    sig { returns(T.nilable(DispatchErrorReporter)) }
    def on_dispatch_error
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

  class DbOperationCollection
    include Enumerable

    sig { void }
    def initialize
    end

    sig { params(persistence_handler: Changeset::Callable).void }
    def add(persistence_handler)
    end

    sig { params(db_operations: Changeset::DbOperationCollection).void }
    def merge_child(db_operations)
    end

    sig { params(block: T.proc.params(arg0: Changeset::Callable).returns(BasicObject)).void }
    def each(&block)
    end

    sig { params(other: Changeset::DbOperationCollection).returns(T::Boolean) }
    def ==(other)
    end

    protected

    sig { returns(T::Array[Changeset::Callable]) }
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

    sig { params(block: T.proc.params(arg0: Changeset::Event).returns(BasicObject)).void }
    def each(&block)
    end

    sig { params(block: T.proc.params(arg0: T::Array[Changeset::Event]).returns(BasicObject)).void }
    def each_group(&block)
    end

    sig { params(other: Changeset::EventCollection).returns(T::Boolean) }
    def ==(other)
    end

    protected

    sig { returns(GroupedEvent) }
    attr_reader :grouped_events

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

  class DeferredMerge
    sig { returns(T.proc.returns(Changeset)) }
    attr_reader :build_child

    sig { params(build_child: T.proc.returns(Changeset)).void }
    def initialize(build_child)
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
end
