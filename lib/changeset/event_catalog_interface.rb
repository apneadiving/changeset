# typed: strict

class Changeset
  module EventCatalogInterface
    def dispatch(event)
    end

    def known_event?(event_name)
      false
    end

    def class
      super
    end
  end
end
