# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::DatabasesController, "CSRF / idempotency", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #index" do
    it "is idempotent — calling twice produces no state changes" do
      count_before = MigrationSkippr::Event.count

      get :index
      expect(response).to have_http_status(:ok)

      get :index
      expect(response).to have_http_status(:ok)

      expect(MigrationSkippr::Event.count).to eq(count_before)
    end
  end

  describe "GET #show" do
    let(:database_name) { "primary" }

    it "is idempotent — calling twice produces no state changes" do
      count_before = MigrationSkippr::Event.count

      get :show, params: {name: database_name}
      expect(response).to have_http_status(:ok)

      get :show, params: {name: database_name}
      expect(response).to have_http_status(:ok)

      expect(MigrationSkippr::Event.count).to eq(count_before)
    end
  end
end
