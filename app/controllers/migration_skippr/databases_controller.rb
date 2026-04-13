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
      migration_file_versions_for(database_name) - ran_versions_for(database_name).to_a
    end

    def build_migration_list(database_name)
      file_versions = migration_file_versions_for(database_name)
      ran_versions = ran_versions_for(database_name)
      skipped_versions = Event.currently_skipped(database_name).map(&:version).to_set

      migrations = file_versions.map { |version| on_disk_migration(version, ran_versions, skipped_versions) }
      migrations.concat(off_disk_migrations(database_name, file_versions))
      migrations.sort_by { |migration| migration[:version] }.last(100)
    end

    def on_disk_migration(version, ran_versions, skipped_versions)
      status = if skipped_versions.include?(version)
        :skipped
      elsif ran_versions.include?(version)
        :ran
      else
        :pending
      end
      {version: version, status: status, on_disk: true}
    end

    def off_disk_migrations(database_name, file_versions)
      event_versions = Event.current_states.where(database_name: database_name).pluck(:version)
      (event_versions - file_versions).map do |version|
        state = Event.current_state_for(database_name, version)
        {version: version, status: state.status.to_sym, on_disk: false}
      end
    end

    def migration_file_versions_for(database_name)
      DatabaseResolver.migration_paths_for(database_name).flat_map do |path|
        Dir[File.join(path, "[0-9]*_*.rb")].map { |file| File.basename(file).match(/\A(\d+)_/)&.captures&.first }
      end.compact.sort
    end

    def ran_versions_for(database_name)
      DatabaseResolver.connection_for(database_name)
        .select_values("SELECT version FROM schema_migrations")
        .map(&:to_s)
        .to_set
    end
  end
end
