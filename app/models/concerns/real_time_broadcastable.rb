# frozen_string_literal: true

# Concern for enabling real-time analytics updates via Turbo Streams
# Include this in models that should trigger analytics dashboard updates
module RealTimeBroadcastable
  extend ActiveSupport::Concern

  included do
    after_commit :broadcast_metric_update, if: :should_broadcast?
  end

  private

  def should_broadcast?
    # Only broadcast if we're in a web request context and business exists
    defined?(business) && business.present? && !Rails.env.test?
  end

  def broadcast_metric_update
    return unless should_broadcast?

    # Broadcast to the business's analytics channel
    broadcast_replace_to(
      [business, "analytics"],
      target: metric_dom_id,
      partial: "business_manager/analytics/metrics/#{metric_type}",
      locals: { metric: calculate_metric }
    )
  rescue StandardError => e
    Rails.logger.error "[RealTimeBroadcastable] Error broadcasting metric: #{e.message}"
  end

  # Override these methods in models that include this concern
  def metric_dom_id
    "#{self.class.name.underscore}_metrics"
  end

  def metric_type
    self.class.name.underscore
  end

  def calculate_metric
    # Override in including class to return current metric value
    nil
  end
end
