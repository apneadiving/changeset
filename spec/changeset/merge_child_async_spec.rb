# typed: ignore

RSpec.describe "Changeset Merge Child Async", with_sorbet: false do
  context "check calls" do
    let(:mocked_worker) { spy("mocked_worker") }
    let(:mocked_worker2) { spy("mocked_worker2") }
    let(:mocked_worker3) { spy("mocked_worker3") }
    let(:event_catalog_klass) do
      Class.new do
        def initialize(mocked_worker)
          @mocked_worker = mocked_worker
        end

        def dispatch(event)
          send(event.name, event.payload)
        end

        def known_event?(event_name)
          %i[my_event].include?(event_name)
        end

        private

        def my_event(payload)
          @mocked_worker.call(payload)
        end
      end
    end

    let(:db_operation1) { spy("db_operation1") }
    let(:db_operation2) { spy("db_operation2") }
    let(:db_operation3) { spy("db_operation3") }
    let(:db_operation4) { spy("db_operation4") }
    let(:changeset) { ::Changeset.new(event_catalog_klass.new(mocked_worker)) }
    let(:child_changeset) { ::Changeset.new(event_catalog_klass.new(mocked_worker2)) }
    let(:grand_child_changeset) { ::Changeset.new(event_catalog_klass.new(mocked_worker3)) }

    before do
      Changeset.configure do |config|
        config.db_transaction_wrapper = ->(&block) { block.call }
      end
    end

    it "triggers db_operations and events" do
      changeset.add_db_operations(
        db_operation1,
        db_operation2
      )
      changeset.add_event(:my_event, {"foo" => 1})

      changeset.merge_child_async do
        child_changeset
          .add_db_operation(db_operation3)
          .add_event(:my_event, {"foo" => 2})
          .merge_child_async do
            grand_child_changeset
              .add_db_operations(db_operation4)
              .add_event(:my_event, {"foo" => 3})
          end
      end

      changeset.push!

      expect(db_operation1).to have_received(:call).ordered
      expect(db_operation2).to have_received(:call).ordered
      expect(db_operation3).to have_received(:call).ordered
      expect(db_operation4).to have_received(:call).ordered
      expect(mocked_worker).to have_received(:call).with({"foo" => 1}).once.ordered
      expect(mocked_worker2).to have_received(:call).with({"foo" => 2}).once.ordered
      expect(mocked_worker3).to have_received(:call).with({"foo" => 3}).once.ordered
    end
  end

  context "check instanciation order" do
    it "triggers db_operations" do
      child_changeset_instantiated = false
      grand_child_changeset_instantiated = false

      db_operation1_called = false
      db_operation2_called = false
      db_operation3_called = false
      db_operation4_called = false
      db_operation5_called = false

      db_operation1 = -> {
        db_operation1_called = true
        expect(child_changeset_instantiated).to be false
      }

      db_operation2 = -> {
        db_operation2_called = true
        expect(grand_child_changeset_instantiated).to be false
      }

      db_operation3 = -> {
        db_operation3_called = true
      }

      db_operation4 = -> {
        db_operation4_called = true
        expect(grand_child_changeset_instantiated).to be true
      }

      db_operation5 = -> {
        db_operation5_called = true
        expect(child_changeset_instantiated).to be true
        expect(grand_child_changeset_instantiated).to be true
      }

      Changeset.new.add_db_operations(
        db_operation1
      ).merge_child_async do
        child_changeset_instantiated = true
        Changeset.new
          .add_db_operation(db_operation2)
          .merge_child_async do
            grand_child_changeset_instantiated = true
            Changeset.new
              .add_db_operations(db_operation3)
          end
          .add_db_operation(db_operation4)
      end
        .add_db_operation(db_operation5)
        .push!

      expect(db_operation1_called).to be true
      expect(db_operation2_called).to be true
      expect(db_operation3_called).to be true
      expect(db_operation4_called).to be true
      expect(db_operation5_called).to be true
    end
  end
end
