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

      # For the primary database, use ActiveRecord::Base's connection directly
      primary_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
      if primary_config && config.name == primary_config.name
        return ActiveRecord::Base.connection
      end

      pool = retrieve_connection_pool(config.name)

      if pool
        pool.connection
      else
        # For databases without an established pool, create a dedicated abstract class
        # to avoid clobbering ActiveRecord::Base's connection
        connection_class = connection_class_for(name)
        connection_class.establish_connection(config)
        connection_class.connection
      end
    end

    def self.connection_class_for(name)
      @connection_classes ||= {}
      @connection_classes[name] ||= begin
        class_name = "MigrationSkipprDb#{name.to_s.classify}"
        klass = Class.new(ActiveRecord::Base) do
          self.abstract_class = true
        end
        MigrationSkippr.const_set(class_name, klass) unless MigrationSkippr.const_defined?(class_name)
        MigrationSkippr.const_get(class_name)
      end
    end

    def self.retrieve_connection_pool(name)
      handler = ActiveRecord::Base.connection_handler
      kwargs = { role: ActiveRecord.writing_role }
      kwargs[:strict] = false if handler.method(:retrieve_connection_pool).parameters.any? { |_, n| n == :strict }
      handler.retrieve_connection_pool(name, **kwargs)
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
