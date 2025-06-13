class LoyaltyTransaction < ApplicationRecord
  include TenantScoped
  
  belongs_to :business, required: true
  belongs_to :tenant_customer, required: true
  belongs_to :related_booking, class_name: 'Booking', optional: true
  belongs_to :related_order, class_name: 'Order', optional: true
  belongs_to :related_referral, class_name: 'Referral', optional: true
  
  validates :business, presence: true
  validates :tenant_customer, presence: true
  validates :transaction_type, presence: true, inclusion: { in: %w[earned redeemed expired adjusted] }
  validates :points_amount, presence: true, numericality: { other_than: 0 }
  validates :description, presence: true
  
  # Clear loyalty cache when transactions change
  after_commit :clear_tenant_customer_loyalty_cache, on: [:create, :update, :destroy]
  
  scope :earned, -> { where(transaction_type: 'earned') }
  scope :redeemed, -> { where(transaction_type: 'redeemed') }
  scope :expired, -> { where(transaction_type: 'expired') }
  scope :adjusted, -> { where(transaction_type: 'adjusted') }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_customer, ->(customer) { where(tenant_customer: customer) }
  
  def earned?
    transaction_type == 'earned'
  end
  
  def redeemed?
    transaction_type == 'redeemed'
  end
  
  def expired?
    transaction_type == 'expired'
  end
  
  def adjusted?
    transaction_type == 'adjusted'
  end
  
  def positive_points?
    points_amount > 0
  end
  
  def negative_points?
    points_amount < 0
  end
  
  # Class methods for point calculations
  def self.total_earned_for_customer(customer)
    earned.for_customer(customer).sum(:points_amount)
  end
  
  def self.total_redeemed_for_customer(customer)
    redeemed.for_customer(customer).sum(:points_amount).abs
  end
  
  def self.current_balance_for_customer(customer)
    for_customer(customer).sum(:points_amount)
  end
  
  private
  
  def clear_tenant_customer_loyalty_cache
    tenant_customer&.clear_loyalty_cache
  end
end 