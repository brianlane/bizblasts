class TipConfiguration < ApplicationRecord
  include TenantScoped
  
  belongs_to :business, required: true
  
  validates :business_id, uniqueness: true
  validates :default_tip_percentages, presence: true
  validates :custom_tip_enabled, inclusion: { in: [true, false] }
  
  def tip_percentage_options
    default_tip_percentages || [15, 18, 20]
  end
  
  def calculate_tip_amounts(base_amount)
    tip_percentage_options.map do |percentage|
      {
        percentage: percentage,
        amount: (base_amount * percentage / 100.0).round(2)
      }
    end
  end
  
  def self.ransackable_attributes(auth_object = nil)
    %w[id business_id default_tip_percentages custom_tip_enabled tip_message created_at updated_at]
  end
  
  def self.ransackable_associations(auth_object = nil)
    %w[business]
  end
end 