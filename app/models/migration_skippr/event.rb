# frozen_string_literal: true

module MigrationSkippr
  class Event < ActiveRecord::Base
    self.table_name = "migration_skippr_events"

    validates :database_name, presence: true
    validates :version, presence: true
    validates :status, presence: true, inclusion: {in: %w[skipped unskipped]}

    scope :for_database, ->(database_name) { where(database_name: database_name) }

    def self.current_states
      subquery = select("MAX(id) as max_id")
        .group(:database_name, :version)

      where(id: subquery.map(&:max_id))
    end

    def self.current_state_for(database_name, version)
      where(database_name: database_name, version: version)
        .order(created_at: :desc, id: :desc)
        .first
    end

    def self.currently_skipped(database_name)
      current_states
        .where(database_name: database_name, status: "skipped")
    end

    def self.history_for(database_name, version)
      where(database_name: database_name, version: version)
        .order(created_at: :asc, id: :asc)
    end

    def readonly?
      persisted?
    end
  end
end
