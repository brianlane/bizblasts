class EstimateMessage < ApplicationRecord
  acts_as_tenant(:business)

  belongs_to :estimate
  belongs_to :business

  # Sender types
  SENDER_TYPES = %w[customer business].freeze

  validates :sender_type, presence: true, inclusion: { in: SENDER_TYPES }
  validates :message, presence: true

  scope :chronological, -> { order(created_at: :asc) }
  scope :from_customer, -> { where(sender_type: 'customer') }
  scope :from_business, -> { where(sender_type: 'business') }

  def from_customer?
    sender_type == 'customer'
  end

  def from_business?
    sender_type == 'business'
  end
end
