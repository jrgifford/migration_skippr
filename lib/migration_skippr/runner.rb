# frozen_string_literal: true

require "zlib"

module MigrationSkippr
  class Runner
    def self.run!(version, database:, actor: nil)
      connection = DatabaseResolver.connection_for(database)

      with_lock(connection, database, version) do
        current = Event.current_state_for(database, version)

        if current&.status == "skipped"
          Skipper.unskip!(version, database: database, actor: actor, note: "Unskipped for execution")
        elsif %w[completed running].include?(current&.status)
          raise AlreadyRanError, "Migration #{version} has already been run on #{database}"
        end

        Event.create!(database_name: database, version: version, status: "running", actor: actor)

        begin
          execute_migration(version, database, connection)
          Skipper.insert_into_schema_migrations(version, database)
          Event.create!(database_name: database, version: version, status: "completed", actor: actor)
        rescue => e
          Event.create!(
            database_name: database, version: version, status: "failed",
            actor: actor, note: e.message
          )
          Skipper.insert_into_schema_migrations(version, database)
          Event.create!(
            database_name: database, version: version, status: "skipped",
            actor: actor, note: "Auto-skipped after failure: #{e.message}"
          )
          raise
        end
      end
    end

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
      # :nocov:
      if postgresql?(connection)
        lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")
        result = connection.select_value("SELECT pg_try_advisory_lock(#{lock_key})")
        raise MigrationAlreadyRunningError, "Migration #{version} is already running on #{database}" unless result
        return
      end
      # :nocov:
      current = Event.current_state_for(database, version)
      raise MigrationAlreadyRunningError, "Migration #{version} is already running on #{database}" if current&.status == "running"
    end
    private_class_method :acquire_lock

    def self.release_lock(connection, database, version)
      # :nocov:
      if postgresql?(connection)
        lock_key = Zlib.crc32("migration_skippr_run_#{database}_#{version}")
        connection.execute("SELECT pg_advisory_unlock(#{lock_key})")
      end
      # :nocov:
    end
    private_class_method :release_lock

    def self.postgresql?(connection)
      connection.adapter_name.downcase.include?("postgresql")
    end
    private_class_method :postgresql?
  end
end
