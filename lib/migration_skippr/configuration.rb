# frozen_string_literal: true

module MigrationSkippr
  class Configuration
    attr_accessor :current_actor, :tracking_database, :authorization_policy

    def initialize
      @current_actor = nil
      @tracking_database = :primary
      @authorization_policy = "MigrationSkippr::MigrationPolicy"
    end
  end
end
