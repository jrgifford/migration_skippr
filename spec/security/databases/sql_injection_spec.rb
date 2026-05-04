# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe MigrationSkippr::DatabasesController, "SQL injection", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  def schema_migrations_exists?
    ActiveRecord::Base.connection.table_exists?(:schema_migrations)
  end

  describe "GET #show" do
    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      context "with SQL payload as database name: #{payload.truncate(40)}" do
        it "raises RecordNotFound and does not corrupt schema_migrations" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)

          expect(schema_migrations_exists?).to be true
        end
      end
    end
  end

  describe "GET #index" do
    it "does not produce a 500" do
      get :index

      expect(response.status).not_to eq(500)
    end
  end

  it "does not modify schema_migrations during read-only #show" do
    initial_count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM schema_migrations").to_i

    SecurityPayloads::SQL_PAYLOADS.each do |payload|
      get :show, params: {name: payload}
    rescue ActiveRecord::RecordNotFound
      # Expected — SQL payloads are not valid database names
    end

    final_count = ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM schema_migrations").to_i
    expect(final_count).to eq(initial_count)
  end
end
