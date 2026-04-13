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

RSpec.describe MigrationSkippr::DatabasesController, "authorization bypass", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  after do
    MigrationSkippr.reset_configuration!
  end

  context "with deny-all policy" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "DenyAllPolicy"
      end
    end

    describe "GET #index" do
      it "raises NotAuthorizedError" do
        expect {
          get :index
        }.to raise_error(MigrationSkippr::NotAuthorizedError)
      end
    end

    describe "GET #show" do
      it "raises NotAuthorizedError" do
        expect {
          get :show, params: {name: database_name}
        }.to raise_error(MigrationSkippr::NotAuthorizedError)
      end
    end
  end

  context "with restrictive policy" do
    before do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "RestrictivePolicy"
      end
    end

    describe "GET #index" do
      it "returns 200 OK" do
        get :index
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET #show" do
      it "returns 200 OK" do
        get :show, params: {name: database_name}
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
