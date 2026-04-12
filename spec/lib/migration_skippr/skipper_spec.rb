# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::Skipper do
  let(:database_name) { "primary" }
  let(:version) { "20260101000099" }

  after do
    connection = MigrationSkippr::DatabaseResolver.connection_for(database_name)
    connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
  rescue StandardError
    nil
  end

  describe ".skip!" do
    it "creates a skipped event" do
      described_class.skip!(version, database: database_name, actor: "alice", note: "test skip")

      event = MigrationSkippr::Event.last
      expect(event.database_name).to eq(database_name)
      expect(event.version).to eq(version)
      expect(event.status).to eq("skipped")
      expect(event.actor).to eq("alice")
      expect(event.note).to eq("test skip")
    end

    it "inserts the version into schema_migrations on the target database" do
      described_class.skip!(version, database: database_name)

      connection = MigrationSkippr::DatabaseResolver.connection_for(database_name)
      result = connection.select_value("SELECT version FROM schema_migrations WHERE version = '#{version}'")
      expect(result).to eq(version)
    end

    it "raises if the migration is already skipped" do
      described_class.skip!(version, database: database_name)

      expect {
        described_class.skip!(version, database: database_name)
      }.to raise_error(MigrationSkippr::AlreadySkippedError)
    end

    it "works without actor or note" do
      described_class.skip!(version, database: database_name)

      event = MigrationSkippr::Event.last
      expect(event.actor).to be_nil
      expect(event.note).to be_nil
    end
  end

  describe ".unskip!" do
    before do
      described_class.skip!(version, database: database_name, actor: "alice")
    end

    it "creates an unskipped event" do
      described_class.unskip!(version, database: database_name, actor: "bob", note: "ready to run")

      event = MigrationSkippr::Event.last
      expect(event.status).to eq("unskipped")
      expect(event.actor).to eq("bob")
      expect(event.note).to eq("ready to run")
    end

    it "removes the version from schema_migrations on the target database" do
      described_class.unskip!(version, database: database_name)

      connection = MigrationSkippr::DatabaseResolver.connection_for(database_name)
      result = connection.select_value("SELECT version FROM schema_migrations WHERE version = '#{version}'")
      expect(result).to be_nil
    end

    it "raises if the migration is not currently skipped" do
      described_class.unskip!(version, database: database_name)

      expect {
        described_class.unskip!(version, database: database_name)
      }.to raise_error(MigrationSkippr::NotSkippedError)
    end
  end
end
