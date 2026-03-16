# typed: strict

class Changeset
  module Errors
    class BaseError < StandardError; end

    class UnknownEventError < BaseError; end

    class MissingConfigurationError < BaseError; end

    class AlreadyPushedError < BaseError; end

    class AlreadyMergedError < BaseError; end

    class AlreadyInTransactionError < BaseError; end
  end
end
