# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Databases XSS protection", type: :request do
  let(:database_name) { "primary" }
  let(:engine_path) { "/migration_skippr" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "XSS payloads as database name parameter" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload: #{payload.truncate(40)}" do
        it "is rejected by routing or raises RecordNotFound" do
          encoded_name = CGI.escape(payload)
          expect {
            get "#{engine_path}/databases/#{encoded_name}"
          }.to raise_error { |error|
            expect(error).to be_a(ActiveRecord::RecordNotFound).or be_a(ActionController::RoutingError)
          }
        end
      end
    end
  end
end

RSpec.describe MigrationSkippr::DatabasesController, "XSS via injected flash", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  let(:database_name) { "primary" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #show" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload in flash[:notice]: #{payload.truncate(40)}" do
        it "escapes the payload in the rendered response" do
          get :show, params: {name: database_name}, flash: {notice: payload}
          expect(response.body).not_to include(payload)
        end
      end

      context "with XSS payload in flash[:alert]: #{payload.truncate(40)}" do
        it "escapes the payload in the rendered response" do
          get :show, params: {name: database_name}, flash: {alert: payload}
          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "GET #index" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload in flash[:notice]: #{payload.truncate(40)}" do
        it "escapes the payload in the rendered response" do
          get :index, flash: {notice: payload}
          expect(response.body).not_to include(payload)
        end
      end

      context "with XSS payload in flash[:alert]: #{payload.truncate(40)}" do
        it "escapes the payload in the rendered response" do
          get :index, flash: {alert: payload}
          expect(response.body).not_to include(payload)
        end
      end
    end
  end
end
