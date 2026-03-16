# typed: ignore

RSpec.describe "Changeset Dispatch", with_sorbet: false do
  let(:dispatch_log) { [] }
  let(:event_catalog_klass) do
    log = dispatch_log
    Class.new do
      define_method(:dispatch) { |event| log << [event.name, event.payload] }
      define_method(:known_event?) { |name| %i[event_a event_b event_c].include?(name) }
    end
  end

  before do
    Changeset.configure do |config|
      config.db_transaction_wrapper = ->(&block) { block.call }
      config.already_in_transaction = nil
    end
  end

  describe "event dispatch order" do
    it "dispatches events in insertion order after dedup" do
      changeset = Changeset.new(event_catalog_klass.new)
      changeset.add_event(:event_a, {order: 1})
      changeset.add_event(:event_b, {order: 2})
      changeset.add_event(:event_a, {order: 1}) # duplicate
      changeset.add_event(:event_c, {order: 3})

      changeset.push!

      expect(dispatch_log).to eq([
        [:event_a, {order: 1}],
        [:event_b, {order: 2}],
        [:event_c, {order: 3}]
      ])
    end
  end

  describe "commit_db_operations and dispatch_events independently" do
    it "commit_db_operations runs operations without dispatching events" do
      op = spy("op")
      changeset = Changeset.new(event_catalog_klass.new)
      changeset.add_db_operation(op)
      changeset.add_event(:event_a, {})

      changeset.commit_db_operations

      expect(op).to have_received(:call)
      expect(dispatch_log).to be_empty
    end

    it "dispatch_events dispatches without running operations" do
      op = spy("op")
      changeset = Changeset.new(event_catalog_klass.new)
      changeset.add_db_operation(op)
      changeset.add_event(:event_a, {val: 1})

      changeset.dispatch_events

      expect(op).not_to have_received(:call)
      expect(dispatch_log).to eq([[:event_a, {val: 1}]])
    end
  end

  describe "db operations with lambdas" do
    it "executes lambda operations in order" do
      call_log = []
      changeset = Changeset.new
      changeset.add_db_operation(-> { call_log << :first })
      changeset.add_db_operation(-> { call_log << :second })
      changeset.add_db_operations(
        -> { call_log << :third },
        -> { call_log << :fourth }
      )

      changeset.push!

      expect(call_log).to eq([:first, :second, :third, :fourth])
    end
  end
end
