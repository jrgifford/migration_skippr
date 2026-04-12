# frozen_string_literal: true

require "rails_helper"
require "generators/migration_skippr/install_generator"

RSpec.describe MigrationSkippr::InstallGenerator, type: :generator do
  destination File.expand_path("../../../tmp/generator_test", __dir__)

  before do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config", "initializers"))
    # Stub the rake task since we're not in a full Rails app
    allow_any_instance_of(described_class).to receive(:install_migrations)
  end

  it "copies the initializer template" do
    run_generator
    assert_file "config/initializers/migration_skippr.rb"
  end

  it "includes configuration block in initializer" do
    run_generator
    assert_file "config/initializers/migration_skippr.rb", /MigrationSkippr\.configure/
  end
end
