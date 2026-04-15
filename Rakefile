# frozen_string_literal: true

require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec

  namespace :spec do
    task :set_security_env do
      ENV["SKIP_COVERAGE_MINIMUM"] = "1"
    end

    RSpec::Core::RakeTask.new(security: :set_security_env) do |t|
      t.pattern = "spec/security/**/*_spec.rb"
    end
  end
rescue LoadError
  # rspec not available in consuming apps
end

namespace :mutant do
  desc "Run mutation tests against security-critical classes"
  task :security do
    sh "bundle", "exec", "mutant", "run",
      "--include", "lib",
      "--require", "migration_skippr",
      "--integration", "rspec",
      "--",
      "MigrationSkippr::Skipper",
      "MigrationSkippr::DatabaseResolver"
  rescue RuntimeError => e
    warn "Mutant task failed: #{e.message}"
    warn "This may be due to a missing mutant-license. See https://github.com/mbj/mutant"
    exit 1
  end
end
