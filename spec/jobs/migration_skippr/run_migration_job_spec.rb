# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::RunMigrationJob, type: :job do
  let(:version) { "20260101000001" }
  let(:database_name) { "primary" }

  describe "#perform" do
    it "delegates to Runner.run!" do
      expect(MigrationSkippr::Runner).to receive(:run!)
        .with(version, database: database_name, actor: "alice")

      described_class.perform_now(version, database_name, actor: "alice")
    end
  end

  describe "error handling" do
    it "discards MigrationAlreadyRunningError" do
      allow(MigrationSkippr::Runner).to receive(:run!)
        .and_raise(MigrationSkippr::MigrationAlreadyRunningError)

      expect {
        described_class.perform_now(version, database_name)
      }.not_to raise_error
    end

    it "discards AlreadyRanError" do
      allow(MigrationSkippr::Runner).to receive(:run!)
        .and_raise(MigrationSkippr::AlreadyRanError)

      expect {
        described_class.perform_now(version, database_name)
      }.not_to raise_error
    end
  end
end
