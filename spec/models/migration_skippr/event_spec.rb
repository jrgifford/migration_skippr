# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::Event, type: :model do
  describe "validations" do
    it "requires database_name" do
      event = described_class.new(version: "20260101000001", status: "skipped")
      expect(event).not_to be_valid
      expect(event.errors[:database_name]).to include("can't be blank")
    end

    it "requires version" do
      event = described_class.new(database_name: "primary", status: "skipped")
      expect(event).not_to be_valid
      expect(event.errors[:version]).to include("can't be blank")
    end

    it "requires status" do
      event = described_class.new(database_name: "primary", version: "20260101000001")
      expect(event).not_to be_valid
      expect(event.errors[:status]).to include("can't be blank")
    end

    it "only allows skipped or unskipped status" do
      event = described_class.new(database_name: "primary", version: "20260101000001", status: "invalid")
      expect(event).not_to be_valid
      expect(event.errors[:status]).to include("is not included in the list")
    end

    it "is valid with all required attributes" do
      event = described_class.new(database_name: "primary", version: "20260101000001", status: "skipped")
      expect(event).to be_valid
    end
  end

  describe ".current_states" do
    it "returns the most recent event per database_name and version" do
      described_class.create!(database_name: "primary", version: "20260101000001", status: "skipped")
      described_class.create!(database_name: "primary", version: "20260101000001", status: "unskipped")
      described_class.create!(database_name: "primary", version: "20260101000002", status: "skipped")

      states = described_class.current_states
      expect(states.length).to eq(2)

      v1_state = states.find { |s| s.version == "20260101000001" }
      v2_state = states.find { |s| s.version == "20260101000002" }

      expect(v1_state.status).to eq("unskipped")
      expect(v2_state.status).to eq("skipped")
    end
  end

  describe ".current_state_for" do
    it "returns the latest event for a specific database and version" do
      described_class.create!(database_name: "primary", version: "20260101000001", status: "skipped")
      described_class.create!(database_name: "primary", version: "20260101000001", status: "unskipped")

      state = described_class.current_state_for("primary", "20260101000001")
      expect(state.status).to eq("unskipped")
    end

    it "returns nil when no events exist" do
      state = described_class.current_state_for("primary", "99999999999999")
      expect(state).to be_nil
    end
  end

  describe ".currently_skipped" do
    it "returns only versions whose latest state is skipped" do
      described_class.create!(database_name: "primary", version: "20260101000001", status: "skipped")
      described_class.create!(database_name: "primary", version: "20260101000002", status: "skipped")
      described_class.create!(database_name: "primary", version: "20260101000002", status: "unskipped")

      skipped = described_class.currently_skipped("primary")
      expect(skipped.map(&:version)).to eq(["20260101000001"])
    end
  end

  describe ".history_for" do
    it "returns all events for a database and version in chronological order" do
      described_class.create!(database_name: "primary", version: "20260101000001", status: "skipped", actor: "alice")
      described_class.create!(database_name: "primary", version: "20260101000001", status: "unskipped", actor: "bob")

      history = described_class.history_for("primary", "20260101000001")
      expect(history.length).to eq(2)
      expect(history.first.actor).to eq("alice")
      expect(history.last.actor).to eq("bob")
    end
  end

  describe "read-only enforcement" do
    it "prevents updating existing records" do
      event = described_class.create!(database_name: "primary", version: "20260101000001", status: "skipped")
      event.status = "unskipped"
      expect { event.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "prevents destroying existing records" do
      event = described_class.create!(database_name: "primary", version: "20260101000001", status: "skipped")
      expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
