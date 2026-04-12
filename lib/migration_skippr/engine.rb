# frozen_string_literal: true

module MigrationSkippr
  class Engine < ::Rails::Engine
    isolate_namespace MigrationSkippr

    initializer "migration_skippr.assets" do |app|
      app.config.assets.precompile += %w[migration_skippr/application.css] if app.config.respond_to?(:assets)
    end
  end
end
