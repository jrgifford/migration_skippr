# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe "Migrations XSS protection", type: :request do
  let(:database_name) { "primary" }
  let(:safe_version) { "20260101000050" }
  let(:engine_path) { "/migration_skippr" }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "stored XSS via note field" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload: #{payload.truncate(40)}" do
        it "does not render the raw payload unescaped in the response" do
          post "#{engine_path}/databases/#{database_name}/migrations",
            params: {version: safe_version, note: payload}

          follow_redirect!
          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "stored XSS via version field" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload: #{payload.truncate(40)}" do
        it "does not render the raw payload unescaped in the response" do
          post "#{engine_path}/databases/#{database_name}/migrations",
            params: {version: payload, note: "test"}

          follow_redirect!
          expect(response.body).not_to include(payload)
        end
      end
    end
  end

  describe "reflected XSS via flash messages" do
    SecurityPayloads::XSS_PAYLOADS.each do |payload|
      context "with XSS payload in version for skip: #{payload.truncate(40)}" do
        it "escapes the payload in the flash message" do
          encoded_version = CGI.escape(payload)
          post "#{engine_path}/databases/#{database_name}/migrations/#{encoded_version}/skip"

          follow_redirect!
          expect(response.body).not_to include(payload)
        rescue ActionController::RoutingError
          # Payload rejected at routing level — no XSS possible
        end
      end

      context "with XSS payload in version for unskip: #{payload.truncate(40)}" do
        it "escapes the payload in the flash message" do
          encoded_version = CGI.escape(payload)
          post "#{engine_path}/databases/#{database_name}/migrations/#{encoded_version}/unskip"

          follow_redirect!
          expect(response.body).not_to include(payload)
        rescue ActionController::RoutingError
          # Payload rejected at routing level — no XSS possible
        end
      end
    end
  end
end
