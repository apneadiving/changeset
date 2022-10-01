# typed: ignore

RSpec.describe Changeset, with_sorbet: false do
  let(:event_catalog_klass) do
    Class.new do
      def dispatch(event)
        send(event.name, event)
      end

      def known_event?(event_name)
        %i[planning_updated].include?(event_name)
      end

      private

      def planning_updated(event)
      end
    end
  end

  let(:other_event_catalog_klass) do
    Class.new do
      def dispatch(event)
        send(event.name, event)
      end

      def known_event?(event_name)
        %i[planning_updated].include?(event_name)
      end

      private

      def planning_updated(event)
      end
    end
  end

  let(:db_operation_klass) do
    Class.new do
      def initialize(some_param)
        @some_param = some_param
      end

      def ==(other)
        some_param == other.some_param
      end

      protected

      attr_reader :some_param
    end
  end

  before do
    Changeset.configure do |config|
      config.db_transaction_wrapper = ->(&block) { block.call }
    end
  end

  context "comparing changesets" do
    let(:changeset1) { Changeset.new(event_catalog_klass.new) }
    let(:changeset2) { Changeset.new(event_catalog_klass.new) }

    context "when empty" do
      it "is equal" do
        expect(changeset1).to eq(changeset2)
      end
    end

    context "only db operations" do
      it "returns true when same collections" do
        changeset1.add_db_operations(
          db_operation_klass.new("db_operation1"),
          db_operation_klass.new("db_operation2")
        )

        changeset2.add_db_operations(
          db_operation_klass.new("db_operation1"),
          db_operation_klass.new("db_operation2")
        )

        expect(changeset1).to eq(changeset2)
      end

      it "returns false when different collections" do
        changeset1.add_db_operations(
          db_operation_klass.new("db_operation1"),
          db_operation_klass.new("db_operation2")
        )

        changeset2.add_db_operations(
          db_operation_klass.new("db_operation2"),
          db_operation_klass.new("db_operation1")
        )

        expect(changeset1).to_not eql(changeset2)
      end
    end

    context "only events" do
      it "returns true when uniq events with same payload" do
        changeset1.add_event(name: :planning_updated, raw_payload: {"foo" => 1})
        changeset1.add_event(name: :planning_updated, raw_payload: {"foo" => 1})

        changeset2.add_event(name: :planning_updated, raw_payload: {"foo" => 1})

        expect(changeset1).to eq(changeset2)
      end

      # not sure we should do this
      it "returns true when uniq events with same payload (evaluates blocks)" do
        changeset1.add_event(name: :planning_updated, raw_payload: {"foo" => 1})

        changeset2.add_event(name: :planning_updated, raw_payload: -> { {"foo" => 1} })

        expect(changeset1).to eq(changeset2)
      end

      it "returns false when events with different payloads" do
        changeset1.add_event(name: :planning_updated, raw_payload: {"foo" => 1})

        changeset2.add_event(name: :planning_updated, raw_payload: {"foo" => 2})

        expect(changeset1).to_not eq(changeset2)
      end

      it "returns false when events with same payload (evaluates blocks)" do
        changeset1.add_event(name: :planning_updated, raw_payload: -> { {"foo" => 1} })

        changeset2.add_event(name: :planning_updated, raw_payload: -> { {"foo" => 2} })

        expect(changeset1).to_not eq(changeset2)
      end

      context "different events catalogs" do
        let(:changeset2) { Changeset.new(other_event_catalog_klass.new) }

        it "returns false event same payload and name" do
          changeset1.add_event(name: :planning_updated, raw_payload: {"foo" => 1})

          changeset2.add_event(name: :planning_updated, raw_payload: {"foo" => 1})

          expect(changeset1).to_not eq(changeset2)
        end
      end
    end
  end
end
