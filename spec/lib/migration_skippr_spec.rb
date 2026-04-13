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

  describe ".skip" do
    let(:database_name) { "primary" }
    let(:version) { "20260101000099" }

    after do
      connection = MigrationSkippr::DatabaseResolver.connection_for(database_name)
      connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
    rescue
      nil
    end

    it "delegates to Skipper.skip!" do
      described_class.skip(version, database: database_name, actor: "alice", note: "test")

      event = MigrationSkippr::Event.last
      expect(event.version).to eq(version)
      expect(event.status).to eq("skipped")
    end
  end

  describe ".unskip" do
    let(:database_name) { "primary" }
    let(:version) { "20260101000098" }

    before { described_class.skip(version, database: database_name) }

    after do
      connection = MigrationSkippr::DatabaseResolver.connection_for(database_name)
      connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
    rescue
      nil
    end

    it "delegates to Skipper.unskip!" do
      described_class.unskip(version, database: database_name, actor: "bob")

      event = MigrationSkippr::Event.last
      expect(event.version).to eq(version)
      expect(event.status).to eq("unskipped")
    end
  end

  describe ".run" do
    it "enqueues a RunMigrationJob" do
      expect {
        described_class.run("20260101000001", database: "primary", actor: "alice")
      }.to have_enqueued_job(MigrationSkippr::RunMigrationJob)
        .with("20260101000001", "primary", actor: "alice")
    end
  end

  describe ".status" do
    it "returns current states for a database" do
      MigrationSkippr::Event.create!(database_name: "primary", version: "20260101000097", status: "skipped")
      result = described_class.status(database: "primary")
      expect(result).to be_present
    end
  end

  describe ".history" do
    it "returns event history for a migration" do
      MigrationSkippr::Event.create!(database_name: "primary", version: "20260101000096", status: "skipped")
      MigrationSkippr::Event.create!(database_name: "primary", version: "20260101000096", status: "unskipped")

      history = described_class.history("20260101000096", database: "primary")
      expect(history.length).to eq(2)
    end
  end
end
