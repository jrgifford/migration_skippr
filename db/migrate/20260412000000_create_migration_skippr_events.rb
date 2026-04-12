# frozen_string_literal: true

class CreateMigrationSkipprEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :migration_skippr_events do |t|
      t.string :database_name, null: false
      t.string :version, null: false
      t.string :status, null: false
      t.string :actor
      t.text :note
      t.datetime :created_at, null: false
    end

    add_index :migration_skippr_events,
      [:database_name, :version, :status, :created_at],
      name: "idx_migration_skippr_events_lookup"
  end
end
