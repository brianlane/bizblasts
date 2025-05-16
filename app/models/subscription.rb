# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :business

  validates :business_id, presence: true, uniqueness: true # One active subscription per business
  validates :plan_name, presence: true
  validates :stripe_subscription_id, presence: true, uniqueness: true
  validates :status, presence: true
  validates :current_period_end, presence: true

  # Define ransackable attributes for ActiveAdmin or other search functionalities
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id plan_name stripe_subscription_id status current_period_end created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[business]
  end
end 