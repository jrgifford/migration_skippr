# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr do
  describe ".configure" do
    after { described_class.reset_configuration! }

    it "yields the configuration object" do
      described_class.configure do |config|
        expect(config).to be_a(MigrationSkippr::Configuration)
      end
    end

    it "persists configuration" do
      described_class.configure do |config|
        config.tracking_database = :analytics
      end
      expect(described_class.configuration.tracking_database).to eq(:analytics)
    end
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(described_class.configuration).to be_a(MigrationSkippr::Configuration)
    end
  end

  describe ".reset_configuration!" do
    it "resets to defaults" do
      described_class.configure { |c| c.tracking_database = :analytics }
      described_class.reset_configuration!
      expect(described_class.configuration.tracking_database).to eq(:primary)
    end
  end
end
