# frozen_string_literal: true

module MigrationSkippr
  class RunMigrationJob < ActiveJob::Base
    queue_as :default
    discard_on MigrationAlreadyRunningError, AlreadyRanError

    def perform(version, database_name, actor: nil)
      Runner.run!(version, database: database_name, actor: actor)
    end
  end
end
