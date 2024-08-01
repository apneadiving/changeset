# typed: true

class Changeset
  class AsyncChangeset
    class InconsistencyError < StandardError; end
    def initialize(changeset_wrapped_in_proc)
      @changeset_wrapped_in_proc = changeset_wrapped_in_proc
      @called = false
    end

    def db_operations
      changeset.send(:db_operations)
    end

    def events_collection
      changeset.send(:events_collection)
    end

    private

    def changeset
      @changeset ||= begin
        @changeset_wrapped_in_proc.call.tap do |result|
          raise InconsistencyError unless result.is_a?(::Changeset)
        end
      end
    end
  end
end
