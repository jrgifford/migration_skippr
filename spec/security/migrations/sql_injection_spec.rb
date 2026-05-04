# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe MigrationSkippr::MigrationsController, "SQL injection", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:safe_version) { "20260101000050" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
    connection = MigrationSkippr::DatabaseResolver.connection_for(database_name)
    connection.execute("DELETE FROM schema_migrations WHERE version = #{connection.quote(safe_version)}")
  rescue ActiveRecord::StatementInvalid
    # Best-effort cleanup — schema_migrations may not exist or row may already be gone
  end

  def schema_migrations_exists?
    ActiveRecord::Base.connection.table_exists?(:schema_migrations)
  end

  describe "POST #create" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "with SQL payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :create, params: {database_name: database_name, version: payload, note: "test"}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end

      context "with SQL payload in note: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :create, params: {database_name: database_name, version: safe_version, note: payload}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end

      context "with SQL payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :create, params: {database_name: payload, version: safe_version}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end
    end
  end

  describe "POST #skip" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "with SQL payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :skip, params: {database_name: database_name, version: payload}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end

      context "with SQL payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :skip, params: {database_name: payload, version: safe_version}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end
    end
  end

  describe "POST #unskip" do
    before do
      MigrationSkippr::Skipper.skip!(safe_version, database: database_name)
    rescue MigrationSkippr::AlreadySkippedError
      # Acceptable for repeated runs
    end

    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "with SQL payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :unskip, params: {database_name: database_name, version: payload}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end

      context "with SQL payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500 or corrupt schema_migrations" do
          post :unskip, params: {database_name: payload, version: safe_version}

          expect(response.status).not_to eq(500)
          expect(schema_migrations_exists?).to be true
        end
      end
    end
  end

  it "does not delete unexpected rows from schema_migrations" do
    initial_count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM schema_migrations").to_i

    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      post :create, params: {database_name: database_name, version: payload}
      post :skip, params: {database_name: database_name, version: payload}
      post :unskip, params: {database_name: database_name, version: payload}
    end

    final_count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM schema_migrations").to_i
    expect(final_count).to be >= initial_count
  end
end
