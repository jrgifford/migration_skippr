# frozen_string_literal: true

module MigrationSkippr
  class DatabasesController < ApplicationController
    def index
      authorize!(:index?)
      @databases = DatabaseResolver.writable_databases
      @database_stats = @databases.each_with_object({}) do |db_name, stats|
        skipped = Event.currently_skipped(db_name)
        pending_count = pending_migrations_for(db_name).count
        stats[db_name] = {skipped: skipped.count, pending: pending_count}
      end
    end

    def show
      authorize!(:show?)
      @database_name = params[:name]
      raise ActiveRecord::RecordNotFound unless DatabaseResolver.writable_databases.include?(@database_name)

      @migrations = build_migration_list(@database_name)
    end

    private

    def pending_migrations_for(database_name)
      paths = DatabaseResolver.migration_paths_for(database_name)
      connection = DatabaseResolver.connection_for(database_name)

      all_versions = migration_files_versions(paths)
      ran_versions = connection.select_values("SELECT version FROM schema_migrations").map(&:to_s)

      all_versions - ran_versions
    end

    def build_migration_list(database_name)
      paths = DatabaseResolver.migration_paths_for(database_name)
      connection = DatabaseResolver.connection_for(database_name)

      file_versions = migration_files_versions(paths)
      ran_versions = connection.select_values("SELECT version FROM schema_migrations").map(&:to_s).to_set
      skipped_versions = Event.currently_skipped(database_name).map(&:version).to_set

      migrations = file_versions.map do |version|
        status = if skipped_versions.include?(version)
          :skipped
        elsif ran_versions.include?(version)
          :ran
        else
          :pending
        end
        {version: version, status: status, on_disk: true}
      end

      all_event_versions = Event.current_states
        .where(database_name: database_name)
        .pluck(:version)
      off_disk_versions = all_event_versions - file_versions

      off_disk_versions.each do |version|
        state = Event.current_state_for(database_name, version)
        migrations << {
          version: version,
          status: state.status.to_sym,
          on_disk: false
        }
      end

      migrations.sort_by { |m| m[:version] }
    end

    def migration_files_versions(paths)
      paths.flat_map do |path|
        Dir[File.join(path, "[0-9]*_*.rb")].map do |file|
          File.basename(file).scan(/\A(\d+)_/).flatten.first
        end
      end.compact.sort
    end
  end
end
