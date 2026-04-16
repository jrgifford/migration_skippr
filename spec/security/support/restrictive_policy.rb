# frozen_string_literal: true

class RestrictivePolicy
  def initialize(actor, record)
    @actor = actor
    @record = record
  end

  def index? = true
  def show? = true
  def skip? = true
  def unskip? = true
  def create? = false
  def run? = false
end
