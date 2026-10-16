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
    @committing = false
  end

  # With a changeset: merges it now, its db operations take this position in the parent's sequence.
  # With a block: the child is built when that position is reached during the commit, so it can
  # read the rows the earlier operations wrote. Its db operations run there, in the same
  # transaction, and its events dispatch after the commit with the parent's.
  def merge_child(child_changeset = nil, &build_child)
    if committing?
      raise Changeset::Errors::CommittingError, "cannot call merge_child from inside a db operation: call it while building the changeset"
    end

    check_open!
    if build_child
      raise ArgumentError, "merge_child takes a changeset or a block, not both" if child_changeset

      return add_db_operation(DeferredMerge.new(build_child))
    end

    raise ArgumentError, "merge_child takes a changeset or a block" if child_changeset.nil?
    raise ArgumentError, "cannot merge a changeset into itself" if child_changeset.equal?(self)
    check_mergeable!(child_changeset)
    events_collection.merge_child(child_changeset.events_collection)
    db_operations.merge_child(child_changeset.db_operations)
    child_changeset.send(:merged!)
    self
  end

  def add_event(name, raw_payload)
    check_open!
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
    check_open!
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
      @committing = true
      begin
        db_operations.each do |operation|
          case operation
          when DeferredMerge then merge_built_child(build_deferred_child(operation))
          else operation.call
          end
        end
      ensure
        @committing = false
      end
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

  def committing?
    @committing
  end

  # Runs while committing, at the position of the block that built the child, on the changeset
  # that commits: after an eager merge, the parent copied the deferred merge in and commits it, so
  # the child's events land in the parent.
  def merge_built_child(child_changeset)
    unless child_changeset.is_a?(Changeset)
      raise Changeset::Errors::NotAChangesetError, "merge_child's block must return a Changeset, got #{child_changeset.class}"
    end

    check_mergeable!(child_changeset)
    child_changeset.commit_db_operations
    events_collection.merge_child(child_changeset.events_collection)
    child_changeset.send(:merged!)
  end

  # The block is a Proc called long after the method that wrote it has returned: a `return` inside
  # it has nowhere to go.
  def build_deferred_child(deferred_merge)
    deferred_merge.build_child.call
  rescue LocalJumpError
    raise ArgumentError, "merge_child's block must not return: end it with the child changeset"
  end

  # A pushed or merged changeset is closed: what is added to it afterwards would run twice or never.
  def check_open!
    raise Changeset::Errors::AlreadyPushedError, "cannot add to a changeset that has already been pushed" if pushed?
    raise Changeset::Errors::AlreadyMergedError, "cannot add to a changeset that has been merged into a parent" if merged?
  end

  def check_mergeable!(child_changeset)
    raise Changeset::Errors::AlreadyPushedError, "cannot merge a changeset that has already been pushed" if child_changeset.pushed?
    raise Changeset::Errors::AlreadyMergedError, "cannot merge a changeset that has already been merged" if child_changeset.merged?
  end

  def merged!
    @merged = true
  end

  def check_not_already_in_transaction!
    checker = Changeset.configuration.already_in_transaction
    return unless checker
    raise Changeset::Errors::AlreadyInTransactionError, "push! called inside an open transaction" if checker.call
  end
end
