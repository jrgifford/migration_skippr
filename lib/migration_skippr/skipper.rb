# frozen_string_literal: true

module MigrationSkippr
  class AlreadySkippedError < StandardError; end
  class NotSkippedError < StandardError; end

  class Skipper
    def self.skip!(version, database:, actor: nil, note: nil)
      current = Event.current_state_for(database, version)
      raise AlreadySkippedError, "Migration #{version} is already skipped on #{database}" if current&.status == "skipped"

      Event.create!(
        database_name: database,
        version: version,
        status: "skipped",
        actor: actor,
        note: note
      )

      insert_into_schema_migrations(version, database)
    end

    def self.unskip!(version, database:, actor: nil, note: nil)
      current = Event.current_state_for(database, version)
      raise NotSkippedError, "Migration #{version} is not skipped on #{database}" unless current&.status == "skipped"

      Event.create!(
        database_name: database,
        version: version,
        status: "unskipped",
        actor: actor,
        note: note
      )

      remove_from_schema_migrations(version, database)
    end

    def self.insert_into_schema_migrations(version, database_name)
      connection = DatabaseResolver.connection_for(database_name)
      connection.execute(
        "INSERT INTO schema_migrations (version) VALUES (#{connection.quote(version)})"
      )
    end
    private_class_method :insert_into_schema_migrations

    def self.remove_from_schema_migrations(version, database_name)
      connection = DatabaseResolver.connection_for(database_name)
      connection.execute(
        "DELETE FROM schema_migrations WHERE version = #{connection.quote(version)}"
      )
    end
    private_class_method :remove_from_schema_migrations
  end
end
