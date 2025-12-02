# frozen_string_literal: true

class SolidQueuePruneJob < ApplicationJob
  queue_as :default

  RETENTION_ENV_KEY = 'SOLID_QUEUE_RETENTION_DAYS'
  DEFAULT_RETENTION_DAYS = 14

  def perform(retention_days: default_retention_days)
    days = retention_days.to_i
    cutoff = days.days.ago
    SolidQueue::Pruner.run(older_than: cutoff)
  end

  private

  def default_retention_days
    Integer(ENV.fetch(RETENTION_ENV_KEY, DEFAULT_RETENTION_DAYS))
  rescue ArgumentError, TypeError
    DEFAULT_RETENTION_DAYS
  end
end

