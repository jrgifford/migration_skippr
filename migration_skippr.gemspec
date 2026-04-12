# frozen_string_literal: true

require_relative "lib/migration_skippr/version"

Gem::Specification.new do |spec|
  spec.name = "migration_skippr"
  spec.version = MigrationSkippr::VERSION
  spec.authors = ["James Gifford"]
  spec.summary = "Skip and manage Rails database migrations via a web UI"
  spec.description = "A Rails engine for marking migrations as skipped (faking them in schema_migrations) " \
                     "and unskipping them later. Supports multiple databases, append-only audit trail, " \
                     "and Pundit-based authorization."
  spec.homepage = "https://github.com/jrgifford/migration-manager"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "db/**/*",
    "lib/**/*",
    "LICENSE.txt"
  ]

  spec.add_dependency "rails", ">= 7.1", "< 9.0"
  spec.add_dependency "pundit", ">= 2.3"
end
