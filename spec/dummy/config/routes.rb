# frozen_string_literal: true

Rails.application.routes.draw do
  mount MigrationSkippr::Engine, at: "/migration_skippr"
end
