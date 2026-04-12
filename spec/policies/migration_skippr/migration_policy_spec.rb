# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationSkippr::MigrationPolicy do
  subject(:policy) { described_class.new(actor, record) }

  let(:actor) { "test_user" }
  let(:record) { nil }

  describe "default deny" do
    it { expect(policy.index?).to be false }
    it { expect(policy.show?).to be false }
    it { expect(policy.skip?).to be false }
    it { expect(policy.unskip?).to be false }
    it { expect(policy.create?).to be false }
  end

  describe "#actor" do
    it "exposes the actor" do
      expect(policy.actor).to eq("test_user")
    end
  end

  describe "#record" do
    let(:record) { double("migration") }

    it "exposes the record" do
      expect(policy.record).to eq(record)
    end
  end

  describe "with nil actor" do
    let(:actor) { nil }

    it "still denies all actions" do
      expect(policy.index?).to be false
      expect(policy.show?).to be false
      expect(policy.skip?).to be false
      expect(policy.unskip?).to be false
      expect(policy.create?).to be false
    end
  end
end
