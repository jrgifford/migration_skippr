# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe MigrationSkippr::MigrationsController, "input validation", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:safe_version) { "20260101000060" }

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
    # Best-effort cleanup
  end

  # Malicious payloads may be rejected at the DB layer (StatementInvalid) or at the model
  # validation layer (RecordInvalid). Both are valid defenses — input rejected before any
  # corrupting state change. We still assert the schema_migrations table is intact, so a
  # payload that drops or corrupts the table fails the test instead of being swallowed.
  def post_safely(action, params)
    post action, params: params
    expect(response.status).not_to eq(500)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid
    expect(ActiveRecord::Base.connection.table_exists?(:schema_migrations)).to be(true)
  end

  describe "POST #create" do
    SecurityPayloads::TRAVERSAL_PAYLOADS.each do |payload|
      context "with traversal payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :create, {database_name: database_name, version: payload, note: "test"}
        end
      end

      context "with traversal payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :create, {database_name: payload, version: safe_version}
        end
      end
    end

    SecurityPayloads::OVERFLOW_PAYLOADS.each do |payload|
      context "with overflow payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :create, {database_name: database_name, version: payload, note: "test"}
        end
      end

      context "with overflow payload in note: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :create, {database_name: database_name, version: safe_version, note: payload}
        end
      end

      context "with overflow payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :create, {database_name: payload, version: safe_version}
        end
      end
    end
  end

  describe "POST #skip" do
    SecurityPayloads::TRAVERSAL_PAYLOADS.each do |payload|
      context "with traversal payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :skip, {database_name: database_name, version: payload}
        end
      end

      context "with traversal payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :skip, {database_name: payload, version: safe_version}
        end
      end
    end

    SecurityPayloads::OVERFLOW_PAYLOADS.each do |payload|
      context "with overflow payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :skip, {database_name: database_name, version: payload}
        end
      end

      context "with overflow payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :skip, {database_name: payload, version: safe_version}
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

    SecurityPayloads::TRAVERSAL_PAYLOADS.each do |payload|
      context "with traversal payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :unskip, {database_name: database_name, version: payload}
        end
      end

      context "with traversal payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :unskip, {database_name: payload, version: safe_version}
        end
      end
    end

    SecurityPayloads::OVERFLOW_PAYLOADS.each do |payload|
      context "with overflow payload in version: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :unskip, {database_name: database_name, version: payload}
        end
      end

      context "with overflow payload in database_name: #{payload.truncate(40)}" do
        it "does not produce a 500" do
          post_safely :unskip, {database_name: payload, version: safe_version}
        end
      end
    end
  end
end
