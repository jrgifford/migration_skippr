# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::DatabasesController, type: :controller do
  routes { MigrationSkippr::Engine.routes }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end

    allow(MigrationSkippr::DatabaseResolver).to receive(:connection_for)
      .and_return(ActiveRecord::Base.connection)
  end

  after { MigrationSkippr.reset_configuration! }

  describe "GET #index" do
    it "returns success" do
      get :index
      expect(response).to have_http_status(:ok)
    end

    it "assigns writable databases" do
      get :index
      expect(assigns(:databases)).to include("primary")
    end

    it "denies access when policy forbids" do
      MigrationSkippr.configure do |config|
        config.authorization_policy = "MigrationSkippr::MigrationPolicy"
      end

      expect { get :index }.to raise_error(MigrationSkippr::NotAuthorizedError)
    end
  end

  describe "GET #show" do
    it "returns success for a valid database" do
      get :show, params: { name: "primary" }
      expect(response).to have_http_status(:ok)
    end

    it "assigns migrations with their statuses" do
      get :show, params: { name: "primary" }
      expect(assigns(:migrations)).to be_an(Array)
    end

    it "returns 404 for unknown database" do
      expect {
        get :show, params: { name: "nonexistent" }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
