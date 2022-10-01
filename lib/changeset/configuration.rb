# typed: true

class Changeset
  class Configuration
    attr_writer :db_transaction_wrapper

    def db_transaction_wrapper
      return @db_transaction_wrapper if @db_transaction_wrapper

      raise Changeset::Errors::MissingConfigurationError, "db_transaction_wrapper"
    end
  end
end
