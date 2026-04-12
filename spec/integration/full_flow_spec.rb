# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Full skip/unskip flow", type: :request do
  let(:database_name) { "primary" }
  let(:version) { "20260101000050" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
    connection = ActiveRecord::Base.connection
    connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
  rescue
    nil
  end

  it "skips a migration, verifies schema_migrations, then unskips" do
    connection = ActiveRecord::Base.connection

    # Skip the migration
    post migration_skippr.skip_database_migration_path(database_name: database_name, version: version)
    expect(response).to redirect_to(migration_skippr.database_path(name: database_name))

    # Verify it's in schema_migrations now
    result = connection.select_value("SELECT version FROM schema_migrations WHERE version = '#{version}'")
    expect(result).to eq(version)

    # Verify event was created
    event = MigrationSkippr::Event.last
    expect(event.status).to eq("skipped")
    expect(event.database_name).to eq(database_name)
    expect(event.version).to eq(version)

    # Verify dashboard loads
    get migration_skippr.root_path
    expect(response).to have_http_status(:ok)

    # Verify database detail loads
    get migration_skippr.database_path(name: database_name)
    expect(response).to have_http_status(:ok)

    # Unskip the migration
    post migration_skippr.unskip_database_migration_path(database_name: database_name, version: version)
    expect(response).to redirect_to(migration_skippr.database_path(name: database_name))

    # Verify it's removed from schema_migrations
    result = connection.select_value("SELECT version FROM schema_migrations WHERE version = '#{version}'")
    expect(result).to be_nil

    # Verify unskip event
    event = MigrationSkippr::Event.last
    expect(event.status).to eq("unskipped")
  end

  it "adds an arbitrary migration version via the create action" do
    arbitrary_version = "99990101000001"

    post migration_skippr.database_migrations_path(database_name: database_name),
      params: {version: arbitrary_version, note: "pre-register test"}

    expect(response).to redirect_to(migration_skippr.database_path(name: database_name))

    event = MigrationSkippr::Event.last
    expect(event.version).to eq(arbitrary_version)
    expect(event.status).to eq("skipped")
    expect(event.note).to eq("pre-register test")

    # Clean up
    connection = ActiveRecord::Base.connection
    connection.execute("DELETE FROM schema_migrations WHERE version = '#{arbitrary_version}'")
  end
end
