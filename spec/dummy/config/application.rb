# frozen_string_literal: true

require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)
require "migration_skippr"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
  end
end
