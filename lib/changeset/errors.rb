# typed: strict

class Changeset
  module Errors
    class BaseError < StandardError; end

    class UnknownEventError < BaseError; end

    class MissingConfigurationError < BaseError; end
  end
end
