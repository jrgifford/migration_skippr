# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::Runner do
  let(:database_name) { "primary" }
  # Use a version that corresponds to an actual migration file in the dummy app
  let(:version) { "20260101000001" }
  let(:connection) { MigrationSkippr::DatabaseResolver.connection_for(database_name) }

  before do
    # Ensure the migration is not in schema_migrations (simulate pending state)
    connection.execute("DELETE FROM schema_migrations WHERE version = '#{version}'")
    # Drop the table if it exists so the migration can run
    connection.execute("DROP TABLE IF EXISTS users")
  end

  after do
    MigrationSkippr::Event.where(version: version).delete_all
    # Restore the table for other tests
    connection.execute("CREATE TABLE IF NOT EXISTS users (id integer PRIMARY KEY, email varchar NOT NULL, created_at datetime NOT NULL, updated_at datetime NOT NULL)")
    # Restore schema_migrations entry
    connection.execute("INSERT OR IGNORE INTO schema_migrations (version) VALUES ('#{version}')")
  end

  describe ".run!" do
    context "when the migration is pending" do
      it "executes the migration and records completed event" do
        described_class.run!(version, database: database_name, actor: "alice")

        events = MigrationSkippr::Event.where(database_name: database_name, version: version).order(:id)
        expect(events.map(&:status)).to eq(%w[running completed])

        result = connection.select_value("SELECT version FROM schema_migrations WHERE version = '#{version}'")
        expect(result).to eq(version)
      end
    end

    context "when the migration is skipped" do
      before do
        MigrationSkippr::Skipper.skip!(version, database: database_name, actor: "alice")
      end

      it "unskips, executes, and records completed" do
        described_class.run!(version, database: database_name, actor: "bob")

        events = MigrationSkippr::Event.where(database_name: database_name, version: version).order(:id)
        statuses = events.map(&:status)
        expect(statuses).to eq(%w[skipped unskipped running completed])
      end
    end

    context "when the migration has already been run" do
      before do
        # Put the version in schema_migrations and mark completed
        connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
        MigrationSkippr::Event.create!(database_name: database_name, version: version, status: "completed")
      end

      it "raises AlreadyRanError" do
        expect {
          described_class.run!(version, database: database_name)
        }.to raise_error(MigrationSkippr::AlreadyRanError)
      end
    end

    context "when the migration is already in schema_migrations (no Event)" do
      before do
        connection.execute("INSERT INTO schema_migrations (version) VALUES ('#{version}')")
      end

      it "raises AlreadyRanError" do
        expect {
          described_class.run!(version, database: database_name)
        }.to raise_error(MigrationSkippr::AlreadyRanError)
      end
    end

    context "when the migration is already running (non-PG fallback)" do
      before do
        MigrationSkippr::Event.create!(database_name: database_name, version: version, status: "running")
      end

      it "raises MigrationAlreadyRunningError" do
        expect {
          described_class.run!(version, database: database_name)
        }.to raise_error(MigrationSkippr::MigrationAlreadyRunningError)
      end
    end

    context "when the migration file is not found" do
      let(:version) { "99999999999999" }

      it "raises MigrationFileNotFoundError" do
        expect {
          described_class.run!(version, database: database_name)
        }.to raise_error(MigrationSkippr::MigrationFileNotFoundError)
      end
    end

    context "when the migration fails" do
      before do
        # Simulate a migration that will fail by creating the table first
        # so the CREATE TABLE in the migration raises an error
        connection.execute("CREATE TABLE IF NOT EXISTS users (id integer PRIMARY KEY, email varchar NOT NULL, created_at datetime NOT NULL, updated_at datetime NOT NULL)")
      end

      it "records failed and skipped events, then re-raises" do
        expect {
          described_class.run!(version, database: database_name)
        }.to raise_error(StandardError)

        events = MigrationSkippr::Event.where(database_name: database_name, version: version).order(:id)
        statuses = events.map(&:status)
        expect(statuses).to include("running", "failed", "skipped")

        failed_event = events.find { |e| e.status == "failed" }
        expect(failed_event.note).to be_present

        skipped_event = events.reverse.find { |e| e.status == "skipped" }
        expect(skipped_event.note).to start_with("Auto-skipped after failure:")

        result = connection.select_value("SELECT version FROM schema_migrations WHERE version = '#{version}'")
        expect(result).to eq(version)
      end
    end
  end
end
