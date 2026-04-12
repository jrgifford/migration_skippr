# frozen_string_literal: true

module MigrationSkippr
  class DatabaseResolver
    def self.writable_databases
      configs = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
      configs.reject { |c| c.replica? || (c.respond_to?(:database_tasks?) && !c.database_tasks?) }
             .map(&:name)
    end

    def self.database_config_for(name)
      ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)
    end

    def self.connection_for(name)
      config = database_config_for(name)
      return ActiveRecord::Base.connection unless config

      pool = ActiveRecord::Base.connection_handler.retrieve_connection_pool(
        config.name,
        role: ActiveRecord.writing_role,
        strict: false
      )

      if pool
        pool.connection
      else
        # Establish a connection for this database config
        ActiveRecord::Base.establish_connection(config)
        ActiveRecord::Base.connection
      end
    end

    def self.migration_paths_for(name)
      config = database_config_for(name)
      return [] unless config

      if config.respond_to?(:migrations_paths) && config.migrations_paths.present?
        Array(config.migrations_paths)
      else
        [Rails.root.join("db", "migrate").to_s]
      end
    end
  end
end
