# frozen_string_literal: true

require "migration_skippr/version"
require "migration_skippr/engine"
require "migration_skippr/configuration"
require "migration_skippr/database_resolver"

module MigrationSkippr
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
