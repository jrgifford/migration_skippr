# frozen_string_literal: true

require "migration_skippr/version"
require "migration_skippr/engine" if defined?(Rails)
require "migration_skippr/configuration"
require "migration_skippr/database_resolver"
require "migration_skippr/skipper"
require "migration_skippr/runner"

module MigrationSkippr
  class NotAuthorizedError < StandardError; end
  class MigrationAlreadyRunningError < StandardError; end
  class AlreadyRanError < StandardError; end
  class MigrationFileNotFoundError < StandardError; end

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

    def skip(version, database:, actor: nil, note: nil)
      Skipper.skip!(version, database: database, actor: actor, note: note)
    end

    def unskip(version, database:, actor: nil, note: nil)
      Skipper.unskip!(version, database: database, actor: actor, note: note)
    end

    def status(database:)
      Event.current_states.where(database_name: database)
    end

    def history(version, database:)
      Event.history_for(database, version)
    end

    def run(version, database:, actor: nil)
      RunMigrationJob.perform_later(version, database, actor: actor)
    end
  end
end
