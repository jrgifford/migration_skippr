# frozen_string_literal: true

require "rails_helper"
require_relative "../support/security_payloads"

RSpec.describe MigrationSkippr::DatabasesController, "input validation", type: :controller do
  routes { MigrationSkippr::Engine.routes }

  before do
    MigrationSkippr.configure do |config|
      config.authorization_policy = "AllowAllPolicy"
    end
  end

  after do
    MigrationSkippr.reset_configuration!
  end

  describe "GET #show" do
    SecurityPayloads::TRAVERSAL_PAYLOADS.each do |payload|
      context "with traversal payload as database name: #{payload.truncate(40)}" do
        it "raises RecordNotFound" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end

    SecurityPayloads::OVERFLOW_PAYLOADS.each do |payload|
      context "with overflow payload as database name: #{payload.truncate(40)}" do
        it "raises RecordNotFound" do
          expect {
            get :show, params: {name: payload}
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
