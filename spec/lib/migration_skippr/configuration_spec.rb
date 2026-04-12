# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::Configuration do
  subject(:config) { described_class.new }

  describe "#current_actor" do
    it "defaults to nil" do
      expect(config.current_actor).to be_nil
    end

    it "accepts a lambda" do
      actor_proc = ->(request) { "test_user" }
      config.current_actor = actor_proc
      expect(config.current_actor).to eq(actor_proc)
    end
  end

  describe "#tracking_database" do
    it "defaults to :primary" do
      expect(config.tracking_database).to eq(:primary)
    end

    it "can be changed" do
      config.tracking_database = :analytics
      expect(config.tracking_database).to eq(:analytics)
    end
  end

  describe "#authorization_policy" do
    it "defaults to MigrationSkippr::MigrationPolicy" do
      expect(config.authorization_policy).to eq("MigrationSkippr::MigrationPolicy")
    end

    it "can be changed" do
      config.authorization_policy = "CustomPolicy"
      expect(config.authorization_policy).to eq("CustomPolicy")
    end
  end
end
