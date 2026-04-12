# frozen_string_literal: true

MigrationSkippr.configure do |config|
  # Lambda that receives the request and returns the current actor (string).
  # Used for audit trail. If not configured, actor will be nil.
  #
  # config.current_actor = ->(request) { request.env["warden"].user&.email }

  # Which database to store migration_skippr_events in.
  # Defaults to :primary.
  #
  # config.tracking_database = :primary

  # Pundit policy class for authorization.
  # Override with your own policy to control access.
  # Default policy denies all access.
  #
  # config.authorization_policy = "MigrationSkippr::MigrationPolicy"
end
