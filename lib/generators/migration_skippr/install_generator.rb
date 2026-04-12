# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

module MigrationSkippr
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    desc "Install MigrationSkippr: copy initializer and install migrations"

    def copy_initializer
      template "initializer.rb", "config/initializers/migration_skippr.rb"
    end

    def install_migrations
      rake "migration_skippr:install:migrations"
    end

    def show_post_install
      say ""
      say "MigrationSkippr installed!", :green
      say ""
      say "Next steps:"
      say "  1. Run: rails db:migrate"
      say "  2. Add to config/routes.rb:"
      say "       mount MigrationSkippr::Engine, at: \"/migration_skippr\""
      say "  3. Configure config/initializers/migration_skippr.rb"
      say ""
    end
  end
end
