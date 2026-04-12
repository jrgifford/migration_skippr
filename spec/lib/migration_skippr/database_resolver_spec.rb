# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::DatabaseResolver do
  describe ".writable_databases" do
    it "returns writable database names" do
      databases = described_class.writable_databases
      expect(databases).to include("primary")
    end

    it "includes secondary databases" do
      databases = described_class.writable_databases
      expect(databases).to include("secondary")
    end

    it "excludes replica databases" do
      databases = described_class.writable_databases
      expect(databases).not_to include("replica")
    end
  end

  describe ".database_config_for" do
    it "returns the config for a named database" do
      config = described_class.database_config_for("primary")
      expect(config).to be_present
      expect(config.adapter).to eq("sqlite3")
    end

    it "returns nil for unknown databases" do
      config = described_class.database_config_for("nonexistent")
      expect(config).to be_nil
    end
  end

  describe ".connection_for" do
    it "returns an ActiveRecord connection for the primary database" do
      connection = described_class.connection_for("primary")
      expect(connection).to respond_to(:execute)
    end

    it "returns a connection for secondary databases" do
      connection = described_class.connection_for("secondary")
      expect(connection).to respond_to(:execute)
    end

    it "uses an existing pool connection when available" do
      mock_connection = double("connection", execute: nil)
      mock_pool = double("pool", connection: mock_connection)

      allow(ActiveRecord::Base.connection_handler).to receive(:retrieve_connection_pool)
        .and_return(mock_pool)

      connection = described_class.connection_for("secondary")
      expect(connection).to eq(mock_connection)
    end

    it "returns a fallback connection for unknown databases" do
      connection = described_class.connection_for("nonexistent")
      expect(connection).to respond_to(:execute)
    end
  end

  describe ".migration_paths_for" do
    it "returns migration paths for primary database" do
      paths = described_class.migration_paths_for("primary")
      expect(paths.any? { |p| p.end_with?("db/migrate") }).to be true
    end
  end
end
