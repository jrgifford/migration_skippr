# frozen_string_literal: true

# Boot the dummy Rails app so mutant can resolve engine-autoloaded constants
# (e.g. MigrationSkippr::Event) when analyzing subjects like Skipper.
ENV["RAILS_ENV"] ||= "test"
require_relative "dummy/config/environment"
