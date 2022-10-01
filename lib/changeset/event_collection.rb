# typed: true

class Changeset
  class EventCollection
    def initialize
      @grouped_events = {}
    end

    def add(name:, raw_payload:, events_catalog:)
      new_event = Event.new(
        name: name,
        raw_payload: raw_payload,
        events_catalog: events_catalog
      )
      add_event(new_event)
    end

    def merge_child(event_collection)
      event_collection.all_events.each do |event|
        add_event(event)
      end
    end

    def each(&block)
      uniq_events.each(&block)
    end

    def ==(other)
      uniq_events == other.uniq_events
    end

    protected

    attr_reader :grouped_events

    # only used for merge
    def all_events
      [].tap do |collection|
        grouped_events.each_value do |events|
          collection.concat(events)
        end
      end
    end

    def uniq_events
      [].tap do |collection|
        grouped_events.each_value do |events|
          collection.concat(events.uniq { |event| event.unicity_key })
        end
      end
    end

    private

    def add_event(event)
      grouped_events[event.name] ||= []
      grouped_events.fetch(event.name).push(event)
    end
  end
end
