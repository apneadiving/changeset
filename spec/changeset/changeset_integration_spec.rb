# # typed: ignore

RSpec.describe "Changeset", with_sorbet: false do
  let(:planning_updated_worker) { spy("planning_updated_worker") }
  let(:event_catalog_klass) do
    Class.new do
      def initialize(planning_updated_worker)
        @planning_updated_worker = planning_updated_worker
      end

      def dispatch(event)
        send(event.name, event)
      end

      def known_event?(event_name)
        %i[planning_updated].include?(event_name)
      end

      private

      def planning_updated(event)
        @planning_updated_worker.call
      end
    end
  end
  let(:db_operation1) { spy("db_operation1") }
  let(:db_operation2) { spy("db_operation2") }
  let(:changeset) { ::Changeset.new(event_catalog_klass.new(planning_updated_worker)) }

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
    changeset.add_event(name: :planning_updated, raw_payload: {"foo" => 1})
    changeset.add_event(name: :planning_updated, raw_payload: -> { {"foo" => 1} })

    changeset.push!

    expect(db_operation1).to have_received(:commit)
    expect(db_operation2).to have_received(:commit)
    expect(planning_updated_worker).to have_received(:call).once
  end
end
