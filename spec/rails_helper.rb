# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Ensure the test database schema is up to date
ActiveRecord::Schema.verbose = false
load Rails.root.join("db/schema.rb")

# Ensure schema_migrations table exists for all writable databases
ActiveRecord::Base.configurations.configs_for(env_name: "test").each do |config|
  next if config.replica?

  pool = MigrationSkippr::DatabaseResolver.retrieve_connection_pool(config.name)
  conn = if pool
    pool.connection
  else
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.connection
  end
  unless conn.table_exists?(:schema_migrations)
    conn.create_table :schema_migrations, id: false do |t|
      t.string :version, null: false
    end
    conn.add_index :schema_migrations, :version, unique: true
  end
end
# Re-establish primary connection
ActiveRecord::Base.establish_connection(:primary)

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
