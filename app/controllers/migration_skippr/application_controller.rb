# frozen_string_literal: true

module MigrationSkippr
  class ApplicationController < ActionController::Base
    layout "migration_skippr"

    before_action :set_actor

    private

    def set_actor
      actor_proc = MigrationSkippr.configuration.current_actor
      @current_actor = actor_proc&.call(request)
    end

    def authorize!(action, record = nil)
      policy_class = MigrationSkippr.configuration.authorization_policy.constantize
      policy = policy_class.new(@current_actor, record)

      unless policy.public_send(action)
        raise MigrationSkippr::NotAuthorizedError
      end
    end
  end
end
