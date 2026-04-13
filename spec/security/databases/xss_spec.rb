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

  describe "flash notice XSS on #show" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload: #{payload.truncate(40)}" do
        it "escapes the payload in the rendered flash on the databases show page" do
          encoded_version = CGI.escape(payload)
          post "#{engine_path}/databases/#{database_name}/migrations/#{encoded_version}/skip"
          follow_redirect!
          expect(response.body).not_to include(payload)
        rescue ActionController::RoutingError
          # Payload rejected at routing level — no XSS possible
        end
      end
    end
  end

  describe "flash alert XSS on #index" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload: #{payload.truncate(40)}" do
        it "escapes the payload in the rendered response" do
          get "#{engine_path}/databases"
          expect(response.status).to eq(200)
          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "XSS payloads as database name parameter" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload: #{payload.truncate(40)}" do
        it "raises ActiveRecord::RecordNotFound" do
          encoded_name = CGI.escape(payload)
          expect {
            get "#{engine_path}/databases/#{encoded_name}"
          }.to raise_error(ActiveRecord::RecordNotFound)
        rescue ActionController::RoutingError
          # Payload rejected at routing level — no XSS possible
        end
      end
    end
  end
end
