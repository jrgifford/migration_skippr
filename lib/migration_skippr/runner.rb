# frozen_string_literal: true

require "zlib"

module MigrationSkippr
  class Runner
    def self.run!(version, database:, actor: nil)
      connection = DatabaseResolver.connection_for(database)

      with_lock(connection, database, version) do
        prepare!(version, database, actor, connection)
        Event.create!(database_name: database, version: version, status: "running", actor: actor)
        execute_and_record(version, database, actor, connection)
      end
    end

    def self.prepare!(version, database, actor, connection)
      current = Event.current_state_for(database, version)
      already_applied = connection.select_value(
        "SELECT version FROM schema_migrations WHERE version = #{connection.quote(version)}"
      ).present?

      if current&.status == "skipped"
        Skipper.unskip!(version, database: database, actor: actor, note: "Unskipped for execution")
      elsif current&.status == "completed" || already_applied
        raise AlreadyRanError, "Migration #{version} has already been run on #{database}"
      end
    end
    private_class_method :prepare!

    def self.execute_and_record(version, database, actor, connection)
      execute_migration(version, database, connection)
      Skipper.insert_into_schema_migrations(version, database)
      Event.create!(database_name: database, version: version, status: "completed", actor: actor)
    rescue => e
      record_failure(version, database, actor, e)
      raise
    end
    private_class_method :execute_and_record

    def self.record_failure(version, database, actor, error)
      message = error.message
      Event.create!(database_name: database, version: version, status: "failed", actor: actor, note: message)
      Skipper.insert_into_schema_migrations(version, database)
      Event.create!(
        database_name: database, version: version, status: "skipped",
        actor: actor, note: "Auto-skipped after failure: #{message}"
      )
    end
    private_class_method :record_failure

    def self.execute_migration(version, database, connection)
      migration_class = load_migration_class(version, database)
      migration = migration_class.new
      migration.exec_migration(connection, :up)
    end
    private_class_method :execute_migration

    def self.load_migration_class(version, database)
      paths = DatabaseResolver.migration_paths_for(database)
      file = paths.flat_map { |path|
        Dir[File.join(path, "#{version}_*.rb")]
      }.first

      raise MigrationFileNotFoundError, "No migration file found for version #{version} in #{database}" unless file

      require file
      class_name = File.basename(file, ".rb").sub(/\A\d+_/, "").camelize
      class_name.constantize
    end
    private_class_method :load_migration_class

    def self.with_lock(connection, database, version)
      acquire_lock(connection, database, version)
      yield
    ensure
      release_lock(connection, database, version)
    end
    private_class_method :with_lock

    def self.acquire_lock(connection, database, version)
      already_running = check_already_running(connection, database, version)
      raise MigrationAlreadyRunningError, "Migration #{version} is already running on #{database}" if already_running
    end
    private_class_method :acquire_lock

    def self.check_already_running(connection, database, version)
      lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")

      # :nocov:
      if postgresql?(connection)
        !connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
      elsif mysql?(connection)
        lock_name = "migration_skippr_#{lock_key}"
        !connection.select_value("SELECT GET_LOCK(#{connection.quote(lock_name)}, 0)")
      else
        # :nocov:
        # SQLite: single-writer architecture mostly prevents concurrent runs,
        # but this Event-based check has a TOCTOU race window.
        Event.current_state_for(database, version)&.status == "running"
      end
    end
    private_class_method :check_already_running

    def self.release_lock(connection, database, version)
      lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")

      # :nocov:
      if postgresql?(connection)
        connection.execute("SELECT pg_advisory_unlock(#{lock_key})")
      elsif mysql?(connection)
        lock_name = "migration_skippr_#{lock_key}"
        connection.execute("SELECT RELEASE_LOCK(#{connection.quote(lock_name)})")
      end
      # :nocov:
    end
    private_class_method :release_lock

    def self.postgresql?(connection)
      connection.adapter_name.downcase.include?("postgresql")
    end
    private_class_method :postgresql?

    def self.mysql?(connection)
      connection.adapter_name.downcase.include?("mysql")
    end
    private_class_method :mysql?
  end
end
