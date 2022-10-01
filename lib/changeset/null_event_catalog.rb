# typed: strict

class Changeset
  class NullEventCatalog
    def dispatch(event)
      raise "No events in NullEventCatalog"
    end

    def known_event?(event_name)
      false
    end
  end
end
