# frozen_string_literal: true

module MigrationSkippr
  class MigrationsController < ApplicationController
    def skip
      authorize!(:skip?)
      Skipper.skip!(params[:version], database: params[:database_name], actor: @current_actor)
      redirect_to database_path(name: params[:database_name]), notice: "Migration #{params[:version]} skipped."
    rescue AlreadySkippedError => e
      redirect_to database_path(name: params[:database_name]), alert: e.message
    end

    def unskip
      authorize!(:unskip?)
      Skipper.unskip!(params[:version], database: params[:database_name], actor: @current_actor)
      redirect_to database_path(name: params[:database_name]), notice: "Migration #{params[:version]} unskipped."
    rescue NotSkippedError => e
      redirect_to database_path(name: params[:database_name]), alert: e.message
    end

    def create
      authorize!(:create?)

      version = params[:version].to_s.strip
      if version.blank?
        redirect_to database_path(name: params[:database_name]), alert: "Version is required."
        return
      end

      Skipper.skip!(version, database: params[:database_name], actor: @current_actor, note: params[:note])
      redirect_to database_path(name: params[:database_name]), notice: "Migration #{version} added and skipped."
    rescue AlreadySkippedError => e
      redirect_to database_path(name: params[:database_name]), alert: e.message
    end
  end
end
