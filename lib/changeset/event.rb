# typed: true

class Changeset
  class Event
    attr_reader :name

    # - if at the time the event is added, we know all params
    #   raw_payload would be a Hash
    # - else, it means we need to wait for db operations to be committed
    #   in this case, raw_payload would be a Proc
    #   example: we need db id of some model which is not created yet
    def initialize(name:, raw_payload:, events_catalog:)
      raise Changeset::Errors::UnknownEventError.new("unknown #{name}") unless events_catalog.known_event?(name)

      @name = name
      @events_catalog = events_catalog
      case raw_payload
      when Proc
        @raw_payload = {}
        @raw_payload_proc = raw_payload
      else
        @raw_payload = raw_payload
        @raw_payload_proc = ->{{}}
      end
    end

    def dispatch
      events_catalog.dispatch(self)
    end

    def unicity_key
      [events_catalog.class, name, payload]
    end

    def payload
      raw_payload.empty? ? raw_payload_proc.call : raw_payload
    end

    def ==(other)
      unicity_key == other.unicity_key
    end

    private

    attr_reader :events_catalog, :raw_payload, :raw_payload_proc
  end
end
