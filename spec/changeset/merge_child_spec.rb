# typed: ignore

RSpec.describe "Changeset Merge Child", with_sorbet: false do
  let(:mocked_worker) { spy("mocked_worker") }
  let(:mocked_worker2) { spy("mocked_worker2") }
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
  let(:changeset) { ::Changeset.new(event_catalog_klass.new(mocked_worker)) }
  let(:child_changeset) { ::Changeset.new(event_catalog_klass.new(mocked_worker2)) }

  before do
    Changeset.configure do |config|
      config.db_transaction_wrapper = ->(&block) { block.call }
    end
  end

  it "triggers db_operations and unique events" do
    changeset.add_db_operations(
      db_operation1,
      db_operation2
    )
    changeset.add_event(:my_event, {"foo" => 1})

    child_changeset.add_db_operation(db_operation3)
    child_changeset.add_event(:my_event, {"foo" => 2})

    changeset.merge_child(child_changeset)

    changeset.push!

    expect(db_operation1).to have_received(:call).ordered
    expect(db_operation2).to have_received(:call).ordered
    expect(db_operation3).to have_received(:call).ordered
    expect(mocked_worker).to have_received(:call).with({"foo" => 1}).once.ordered
    expect(mocked_worker2).to have_received(:call).with({"foo" => 2}).once.ordered
  end
end
