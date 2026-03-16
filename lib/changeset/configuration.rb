# typed: true

class Changeset
  class Configuration
    attr_writer :db_transaction_wrapper, :already_in_transaction
    attr_reader :already_in_transaction

    def db_transaction_wrapper
      return @db_transaction_wrapper if @db_transaction_wrapper

      raise Changeset::Errors::MissingConfigurationError, "db_transaction_wrapper"
    end
  end
end
