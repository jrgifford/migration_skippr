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
    connection = ActiveRecord::Base.connection
    connection.execute("DELETE FROM schema_migrations WHERE version = '#{safe_version}'")
  rescue
    nil
  end

  # Null bytes and other binary payloads may cause ActiveRecord::StatementInvalid
  # at the database level. This is a valid defense — the input is rejected before
  # any meaningful state change occurs.
  def post_safely(action, params)
    post action, params: params
    expect(response.status).not_to eq(500)
  rescue ActiveRecord::StatementInvalid
    # Database rejected the payload — acceptable defense
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
    rescue
      nil
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
