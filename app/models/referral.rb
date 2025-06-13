class Referral < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :referrer, class_name: 'User'
  belongs_to :referred_tenant_customer, class_name: 'TenantCustomer', optional: true
  belongs_to :qualifying_booking, class_name: 'Booking', optional: true
  belongs_to :qualifying_order, class_name: 'Order', optional: true
  has_many :discount_codes, foreign_key: 'generated_by_referral_id', dependent: :destroy
  has_many :loyalty_transactions, foreign_key: 'related_referral_id', dependent: :destroy
  
  validates :referral_code, presence: true, uniqueness: { scope: :business_id }
  validates :status, presence: true, inclusion: { in: %w[pending qualified rewarded] }
  
  scope :pending, -> { where(status: 'pending') }
  scope :qualified, -> { where(status: 'qualified') }
  scope :rewarded, -> { where(status: 'rewarded') }
  scope :recent, -> { order(created_at: :desc) }
  
  before_validation :generate_unique_code, on: :create
  
  def pending?
    status == 'pending'
  end
  
  def qualified?
    status == 'qualified'
  end
  
  def rewarded?
    status == 'rewarded'
  end
  
  def mark_qualified!(qualifying_record, customer)
    return unless pending?
    
    update!(
      status: 'qualified',
      referred_tenant_customer: customer,
      qualifying_booking: qualifying_record.is_a?(Booking) ? qualifying_record : nil,
      qualifying_order: qualifying_record.is_a?(Order) ? qualifying_record : nil,
      qualification_met_at: Time.current
    )
  end
  
  def mark_rewarded!
    return unless qualified?
    update!(status: 'rewarded', reward_issued_at: Time.current)
  end
  
  private
  
  def generate_unique_code
    return if referral_code.present?
    
    # Get the business_id to scope the uniqueness check
    biz_id = business_id || business&.id
    
    loop do
      self.referral_code = "REF-#{SecureRandom.alphanumeric(8).upcase}"
      # If we don't have a business_id yet, just generate the code and let uniqueness validation handle it
      break unless biz_id && Referral.exists?(business_id: biz_id, referral_code: referral_code)
    end
  end
end 