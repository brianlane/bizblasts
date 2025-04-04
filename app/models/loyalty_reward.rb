class LoyaltyReward < ApplicationRecord
  include TenantScoped
  
  belongs_to :loyalty_program
  
  validates :name, presence: true
  validates :description, presence: true
  validates :points_required, presence: true, numericality: { greater_than: 0 }
  validates :active, inclusion: { in: [true, false] }
  
  scope :active, -> { where(active: true) }
  scope :by_points_asc, -> { order(points_required: :asc) }
  
  def available_for?(customer_points)
    active? && customer_points >= points_required
  end
  
  def redeem_for(customer)
    # Placeholder for redemption logic
    # Returns true if successful, false otherwise
    if available_for?(customer.loyalty_points)
      # customer.deduct_loyalty_points(points_required, "Redeemed for #{name}")
      # Create redemption record
      true
    else
      false
    end
  end
end 