# frozen_string_literal: true

module MigrationSkippr
  class DatabaseResolver
    def self.writable_databases
      ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
        .reject { |config| config.replica? || skips_database_tasks?(config) }
        .map(&:name)
    end

    def self.skips_database_tasks?(config)
      config.respond_to?(:database_tasks?) && !config.database_tasks?
    end

    def self.database_config_for(name)
      ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: name)
    end

    def self.connection_for(name)
      config = database_config_for(name)
      return base_connection unless config
      return base_connection if primary_database?(config)

      pool = retrieve_connection_pool(config.name)
      return pool.connection if pool

      klass = connection_class_for(name)
      klass.establish_connection(config)
      klass.connection
    end

    def self.primary_database?(config)
      primary = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
      primary && config.name == primary.name
    end

    def self.base_connection
      ActiveRecord::Base.connection
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
      kwargs = {role: ActiveRecord.writing_role}
      kwargs[:strict] = false if handler.method(:retrieve_connection_pool).parameters.any? { |_, n| n == :strict }
      handler.retrieve_connection_pool(name, **kwargs)
    end

    def self.migration_paths_for(name)
      config = database_config_for(name)
      return [] unless config

      paths = config.try(:migrations_paths)
      paths.present? ? Array(paths) : [Rails.root.join("db", "migrate").to_s]
    end
  end
end
