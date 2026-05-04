# frozen_string_literal: true

require "rails_helper"
require_relative "../support/restrictive_policy"

# Deny-all policy for authorization bypass testing
class DenyAllPolicy
  def initialize(actor, record)
    @actor = actor
    @record = record
  end

  def index? = false
  def show? = false
  def skip? = false
  def unskip? = false
  def create? = false
  def run? = false
end

RSpec.describe MigrationSkippr::MigrationsController, "authorization bypass", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:safe_version) { "20260101000050" }

  after do
    MigrationSkippr.reset_configuration!
  end

  context "with deny-all policy" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "DenyAllPolicy"
      end
    end

    describe "POST #skip" do
      it "raises NotAuthorizedError" do
        expect {
          post :skip, params: {database_name: database_name, version: safe_version}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)
      end

      it "does not create an Event" do
        count_before = MigrationSkippr::Event.count

        expect {
          post :skip, params: {database_name: database_name, version: safe_version}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)

        expect(MigrationSkippr::Event.count).to eq(count_before)
      end
    end

    describe "POST #unskip" do
      it "raises NotAuthorizedError" do
        expect {
          post :unskip, params: {database_name: database_name, version: safe_version}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)
      end

      it "does not create an Event" do
        count_before = MigrationSkippr::Event.count

        expect {
          post :unskip, params: {database_name: database_name, version: safe_version}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)

        expect(MigrationSkippr::Event.count).to eq(count_before)
      end
    end

    describe "POST #create" do
      it "raises NotAuthorizedError" do
        expect {
          post :create, params: {database_name: database_name, version: safe_version, note: "test"}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)
      end

      it "does not create an Event" do
        count_before = MigrationSkippr::Event.count

        expect {
          post :create, params: {database_name: database_name, version: safe_version, note: "test"}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)

        expect(MigrationSkippr::Event.count).to eq(count_before)
      end
    end
  end

  context "with restrictive policy" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "RestrictivePolicy"
      end
    end

    describe "POST #skip" do
      it "succeeds with redirect" do
        post :skip, params: {database_name: database_name, version: safe_version}
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "POST #unskip" do
      it "succeeds with redirect after seeding a skipped migration" do
        MigrationSkippr::Skipper.skip!(safe_version, database: database_name)
        post :unskip, params: {database_name: database_name, version: safe_version}
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "POST #create" do
      it "raises NotAuthorizedError" do
        expect {
          post :create, params: {database_name: database_name, version: safe_version, note: "test"}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)
      end
    end
  end
end
