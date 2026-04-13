# frozen_string_literal: true

module MigrationSkippr
  class MigrationPolicy
    attr_reader :actor, :record

    def initialize(actor, record)
      @actor = actor
      @record = record
    end

    def index?
      false
    end

    def show?
      false
    end

    def skip?
      false
    end

    def unskip?
      false
    end

    def create?
      false
    end

    def run?
      false
    end
  end
end
