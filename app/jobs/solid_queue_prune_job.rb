# frozen_string_literal: true

class SolidQueuePruneJob < ApplicationJob
  queue_as :default

  RETENTION_ENV_KEY = 'SOLID_QUEUE_RETENTION_DAYS'
  DEFAULT_RETENTION_DAYS = 14

  def perform(first_arg = nil, **kwargs)
    days = extract_retention_days(first_arg, kwargs)
    cutoff = days.days.ago
    SolidQueue::Pruner.run(older_than: cutoff)
  end

  private

  def default_retention_days
    Integer(ENV.fetch(RETENTION_ENV_KEY, DEFAULT_RETENTION_DAYS))
  rescue ArgumentError, TypeError
    DEFAULT_RETENTION_DAYS
  end

  def extract_retention_days(first_arg, kwargs)
    return normalize_days(kwargs[:retention_days] || kwargs['retention_days']) if kwargs.any?
    return normalize_days(first_arg[:retention_days] || first_arg['retention_days']) if first_arg.is_a?(Hash)

    normalize_days(first_arg) || default_retention_days
  end

  def normalize_days(value)
    return nil if value.nil?
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end
end

