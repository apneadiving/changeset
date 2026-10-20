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

  describe "a raising listener" do
    let(:failing_events) { {} }
    let(:event_catalog_klass) do
      log = dispatch_log
      failing = failing_events
      Class.new do
        define_method(:dispatch) do |event|
          payload = event.payload
          raise failing[payload] if failing.key?(payload)
          log << [event.name, payload]
        end
        define_method(:known_event?) { |name| %i[event_a event_b event_c].include?(name) }
      end
    end
    let(:reported) { [] }

    after do
      Changeset.configuration.on_dispatch_error = nil
      Changeset.configuration.already_in_transaction = nil
    end

    def changeset_with_three_events
      Changeset.new(event_catalog_klass.new)
        .add_event(:event_a, {order: 1})
        .add_event(:event_b, {order: 2})
        .add_event(:event_c, {order: 3})
    end

    def report_to_list
      Changeset.configuration.on_dispatch_error = ->(error, event) { reported << [error, event.name] }
    end

    it "dispatches the other events, then raises its error" do
      error = RuntimeError.new("boom")
      failing_events[{order: 1}] = error

      expect { changeset_with_three_events.push! }.to raise_error(error)
      expect(dispatch_log).to eq([[:event_b, {order: 2}], [:event_c, {order: 3}]])
    end

    it "dispatches the other events of its group" do
      failing_events[{order: 1}] = RuntimeError.new("boom")
      changeset = Changeset.new(event_catalog_klass.new)
        .add_event(:event_a, {order: 1})
        .add_event(:event_a, {order: 2})

      expect { changeset.push! }.to raise_error("boom")
      expect(dispatch_log).to eq([[:event_a, {order: 2}]])
    end

    it "raises the first error and hands the others to on_dispatch_error, with their event" do
      first = RuntimeError.new("first")
      second = ArgumentError.new("second")
      failing_events[{order: 1}] = first
      failing_events[{order: 3}] = second
      report_to_list

      expect { changeset_with_three_events.push! }.to raise_error(first)
      expect(reported).to eq([[second, :event_c]])
      expect(dispatch_log).to eq([[:event_b, {order: 2}]])
    end

    it "does not call on_dispatch_error for a single error" do
      failing_events[{order: 2}] = RuntimeError.new("boom")
      report_to_list

      expect { changeset_with_three_events.push! }.to raise_error("boom")
      expect(reported).to be_empty
    end

    it "calls on_dispatch_error once every event is dispatched" do
      failing_events[{order: 1}] = RuntimeError.new("first")
      failing_events[{order: 2}] = RuntimeError.new("second")
      log = dispatch_log
      Changeset.configuration.on_dispatch_error = ->(error, event) { reported << log.dup }

      expect { changeset_with_three_events.push! }.to raise_error("first")
      expect(reported).to eq([[[:event_c, {order: 3}]]])
    end

    it "raises the first error, reports the others and warns when on_dispatch_error raises" do
      first = RuntimeError.new("first")
      failing_events[{order: 1}] = first
      failing_events[{order: 2}] = RuntimeError.new("second")
      failing_events[{order: 3}] = RuntimeError.new("third")
      Changeset.configuration.on_dispatch_error = lambda do |error, event|
        reported << error.message
        raise "reporter down"
      end

      expect { changeset_with_three_events.push! }
        .to raise_error(first)
        .and output(/on_dispatch_error raised RuntimeError: reporter down.*event_b.*second.*event_c.*third/m).to_stderr
      expect(reported).to eq(["second", "third"])
    end

    it "raises the first error and warns the others when on_dispatch_error is not configured" do
      failing_events[{order: 1}] = RuntimeError.new("first")
      failing_events[{order: 2}] = RuntimeError.new("second")

      expect { changeset_with_three_events.push! }
        .to raise_error("first")
        .and output(/event_b dispatch raised RuntimeError: second/).to_stderr
      expect(dispatch_log).to eq([[:event_c, {order: 3}]])
    end

    it "behaves the same when dispatch_events is called directly" do
      failing_events[{order: 1}] = RuntimeError.new("first")
      failing_events[{order: 2}] = RuntimeError.new("second")
      report_to_list

      expect { changeset_with_three_events.dispatch_events }.to raise_error("first")
      expect(reported.map { |error, name| [error.message, name] }).to eq([["second", :event_b]])
      expect(dispatch_log).to eq([[:event_c, {order: 3}]])
    end

    context "with a proc payload that raises" do
      it "dispatches the other events when it is alone in its group" do
        changeset = Changeset.new(event_catalog_klass.new)
          .add_event(:event_a, -> { raise "payload" })
          .add_event(:event_b, {order: 2})

        expect { changeset.push! }.to raise_error("payload")
        expect(dispatch_log).to eq([[:event_b, {order: 2}]])
      end

      it "dispatches the other events when its group has others" do
        changeset = Changeset.new(event_catalog_klass.new)
          .add_event(:event_a, -> { raise "payload" })
          .add_event(:event_a, {order: 1})
          .add_event(:event_b, {order: 2})

        expect { changeset.push! }.to raise_error("payload")
        expect(dispatch_log).to eq([[:event_a, {order: 1}], [:event_b, {order: 2}]])
      end
    end

    it "reports every collected error when an exception that is not a StandardError follows" do
      first = RuntimeError.new("first")
      shutdown = Class.new(Exception) # standard:disable Lint/InheritException
      failing_events[{order: 1}] = first
      failing_events[{order: 2}] = shutdown.new("shutdown")
      report_to_list

      expect { changeset_with_three_events.push! }.to raise_error(shutdown)
      expect(reported).to eq([[first, :event_a]])
      expect(dispatch_log).to be_empty
    end

    it "stops at the first error inside an open transaction, which it would not roll back" do
      failing_events[{order: 1}] = RuntimeError.new("first")
      failing_events[{order: 2}] = RuntimeError.new("second")
      report_to_list
      changeset = changeset_with_three_events
      Changeset.configuration.already_in_transaction = -> { true }

      expect { changeset.push!(skip_transaction_check: true) }.to raise_error("first")
      expect(dispatch_log).to be_empty
      expect(reported).to be_empty
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
