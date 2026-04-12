# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::MigrationsController, type: :controller do
  routes { MigrationSkippr::Engine.routes }

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
  rescue StandardError
    nil
  end

  describe "POST #skip" do
    it "skips the migration and redirects" do
      post :skip, params: { database_name: database_name, version: version }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:notice]).to include("skipped")
    end

    it "sets flash alert when already skipped" do
      MigrationSkippr::Skipper.skip!(version, database: database_name)

      post :skip, params: { database_name: database_name, version: version }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:alert]).to be_present
    end

    it "denies access when policy forbids" do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "MigrationSkippr::MigrationPolicy"
      end

      expect {
        post :skip, params: { database_name: database_name, version: version }
      }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end
  end

  describe "POST #unskip" do
    before do
      MigrationSkippr::Skipper.skip!(version, database: database_name)
    end

    it "unskips the migration and redirects" do
      post :unskip, params: { database_name: database_name, version: version }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:notice]).to include("unskipped")
    end

    it "sets flash alert when not skipped" do
      MigrationSkippr::Skipper.unskip!(version, database: database_name)

      post :unskip, params: { database_name: database_name, version: version }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:alert]).to be_present
    end
  end

  describe "POST #create" do
    let(:version) { "99990101000001" }

    it "creates a new skipped migration and redirects" do
      post :create, params: { database_name: database_name, version: version, note: "pre-register" }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:notice]).to include("added and skipped")

      event = MigrationSkippr::Event.last
      expect(event.version).to eq(version)
      expect(event.status).to eq("skipped")
      expect(event.note).to eq("pre-register")
    end

    it "sets flash alert when version is blank" do
      post :create, params: { database_name: database_name, version: "" }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:alert]).to be_present
    end

    it "sets flash alert when version is already skipped" do
      MigrationSkippr::Skipper.skip!(version, database: database_name)

      post :create, params: { database_name: database_name, version: version }

      expect(response).to redirect_to(database_path(name: database_name))
      expect(flash[:alert]).to be_present
    end
  end
end
