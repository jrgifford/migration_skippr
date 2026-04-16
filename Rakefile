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
    minimum_coverage = 70.0
    cmd = %w[
      bundle exec mutant run
      --include lib
      --include spec
      --require mutant_boot
      --integration rspec
      --integration-argument spec/lib/
      --
      MigrationSkippr::Skipper
      MigrationSkippr::DatabaseResolver
    ]
    output = IO.popen(cmd, err: [:child, :out], &:read)
    puts output

    if (match = output.match(/Coverage:\s+([\d.]+)%/))
      coverage = match[1].to_f
      if coverage < minimum_coverage
        abort "Mutation coverage #{coverage}% is below minimum #{minimum_coverage}%"
      else
        puts "Mutation coverage #{coverage}% meets minimum #{minimum_coverage}%"
      end
    else
      abort "Could not parse mutation coverage from output"
    end
  end
end
