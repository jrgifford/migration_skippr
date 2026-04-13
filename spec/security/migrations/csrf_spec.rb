# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::MigrationsController, "CSRF protection", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }
  let(:safe_version) { "20260101000050" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
    ActionController::Base.allow_forgery_protection = true
  end

  after do
    ActionController::Base.allow_forgery_protection = false
    MigrationSkippr.reset_configuration!
  end

  describe "POST #create" do
    it "raises InvalidAuthenticityToken without a CSRF token" do
      expect {
        post :create, params: {database_name: database_name, version: safe_version, note: "test"}
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "does not create an Event when CSRF is rejected" do
      count_before = MigrationSkippr::Event.count

      expect {
        post :create, params: {database_name: database_name, version: safe_version, note: "test"}
      }.to raise_error(ActionController::InvalidAuthenticityToken)

      expect(MigrationSkippr::Event.count).to eq(count_before)
    end
  end

  describe "POST #skip" do
    it "raises InvalidAuthenticityToken without a CSRF token" do
      expect {
        post :skip, params: {database_name: database_name, version: safe_version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "does not create an Event when CSRF is rejected" do
      count_before = MigrationSkippr::Event.count

      expect {
        post :skip, params: {database_name: database_name, version: safe_version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)

      expect(MigrationSkippr::Event.count).to eq(count_before)
    end
  end

  describe "POST #unskip" do
    it "raises InvalidAuthenticityToken without a CSRF token" do
      expect {
        post :unskip, params: {database_name: database_name, version: safe_version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "does not create an Event when CSRF is rejected" do
      count_before = MigrationSkippr::Event.count

      expect {
        post :unskip, params: {database_name: database_name, version: safe_version}
      }.to raise_error(ActionController::InvalidAuthenticityToken)

      expect(MigrationSkippr::Event.count).to eq(count_before)
    end
  end
end
