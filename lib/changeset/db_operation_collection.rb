# typed: true

class Changeset
  class DbOperationCollection
    include Enumerable

    def initialize
      @collection = []
    end

    def add(persistence_handler)
      collection.push(persistence_handler)
    end

    def merge_child(db_operations)
      db_operations.collection.each do |db_operation|
        add(db_operation)
      end
    end

    def each(&)
      collection.each(&)
    end

    def ==(other)
      collection == other.collection
    end

    protected

    attr_reader :collection
  end
end
