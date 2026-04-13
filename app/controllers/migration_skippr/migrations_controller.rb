# frozen_string_literal: true

module MigrationSkippr
  class MigrationsController < ApplicationController
    before_action :set_database_name
    before_action :set_version, only: [:skip, :unskip, :run]

    def skip
      authorize!(:skip?)
      Skipper.skip!(@version, database: @database_name, actor: @current_actor)
      redirect_to database_path(name: @database_name), notice: "Migration #{@version} skipped."
    rescue AlreadySkippedError => e
      redirect_to database_path(name: @database_name), alert: e.message
    end

    def unskip
      authorize!(:unskip?)
      Skipper.unskip!(@version, database: @database_name, actor: @current_actor)
      redirect_to database_path(name: @database_name), notice: "Migration #{@version} unskipped."
    rescue NotSkippedError => e
      redirect_to database_path(name: @database_name), alert: e.message
    end

    def run
      authorize!(:run?)
      MigrationSkippr.run(@version, database: @database_name, actor: @current_actor)
      redirect_to database_path(name: @database_name), notice: "Migration #{@version} enqueued for execution."
    end

    def create
      authorize!(:create?)

      version = params[:version].to_s.strip
      if version.blank?
        redirect_to database_path(name: @database_name), alert: "Version is required."
        return
      end

      Skipper.skip!(version, database: @database_name, actor: @current_actor, note: params[:note])
      redirect_to database_path(name: @database_name), notice: "Migration #{version} added and skipped."
    rescue AlreadySkippedError => e
      redirect_to database_path(name: @database_name), alert: e.message
    end

    private

    def set_database_name
      @database_name = params[:database_name]
    end

    def set_version
      @version = params[:version]
    end
  end
end
