# typed: true

class Changeset
  class DbOperationCollection
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

    def merge_child_async(async_change_set)
      add(async_change_set)
      self
    end

    def each(&block)
      collection.each do |element|
        case element
        when Changeset::AsyncChangeset
          element.db_operations.each do |operation|
            yield(operation)
          end
        else
          yield(element)
        end
      end
    end

    def ==(other)
      collection == other.collection
    end

    protected

    attr_reader :collection
  end
end
