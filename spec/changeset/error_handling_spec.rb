# typed: ignore

RSpec.describe "Changeset Error Handling", with_sorbet: false do
  before do
    Changeset.configure do |config|
      config.db_transaction_wrapper = ->(&block) { block.call }
      config.already_in_transaction = nil
    end
  end

  describe "UnknownEventError" do
    let(:event_catalog_klass) do
      Class.new do
        def dispatch(event)
        end

        def known_event?(event_name)
          %i[known_event].include?(event_name)
        end
      end
    end

    it "raises when adding an unknown event" do
      changeset = Changeset.new(event_catalog_klass.new)

      expect { changeset.add_event(:unknown_event, {}) }.to raise_error(
        Changeset::Errors::UnknownEventError,
        "unknown unknown_event"
      )
    end

    it "does not raise for a known event" do
      changeset = Changeset.new(event_catalog_klass.new)

      expect { changeset.add_event(:known_event, {}) }.not_to raise_error
    end
  end

  describe "MissingConfigurationError" do
    it "raises when db_transaction_wrapper is not configured" do
      # Reset configuration
      Changeset.instance_variable_set(:@configuration, Changeset::Configuration.new)

      changeset = Changeset.new
      changeset.add_db_operation(-> {})

      expect { changeset.push! }.to raise_error(Changeset::Errors::MissingConfigurationError)
    end
  end

  describe "NullEventCatalog" do
    it "rejects all events" do
      changeset = Changeset.new # uses NullEventCatalog by default

      expect { changeset.add_event(:anything, {}) }.to raise_error(Changeset::Errors::UnknownEventError)
    end
  end

  describe "rollback on failure" do
    it "does not dispatch events if a db operation raises" do
      mocked_worker = spy("mocked_worker")
      event_catalog_klass = Class.new do
        define_method(:initialize) { |worker| @worker = worker }
        define_method(:dispatch) { |event| @worker.call }
        define_method(:known_event?) { |name| name == :my_event }
      end

      changeset = Changeset.new(event_catalog_klass.new(mocked_worker))
      changeset
        .add_db_operation(-> { raise "boom" })
        .add_event(:my_event, {})

      expect { changeset.push! }.to raise_error("boom")
      expect(mocked_worker).not_to have_received(:call)
    end
  end
end
