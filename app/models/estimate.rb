class Estimate < ApplicationRecord
  include TenantScoped
  acts_as_tenant(:business)

  belongs_to :business
  belongs_to :tenant_customer, optional: true
  belongs_to :booking, optional: true

  has_many :estimate_items, dependent: :destroy
  accepts_nested_attributes_for :estimate_items, allow_destroy: true, reject_if: ->(attrs) { attrs['qty'].to_i <= 0 && attrs['description'].blank? }
  accepts_nested_attributes_for :tenant_customer, reject_if: ->(attrs) { attrs['first_name'].blank? && attrs['last_name'].blank? && attrs['email'].blank? }

  enum :status, { draft: 0, sent: 1, viewed: 2, approved: 3, declined: 4, cancelled: 5 }

  validates :first_name, :last_name, :email, :phone, :address, :city, :state, :zip,
            presence: true, if: -> { tenant_customer_id.blank? }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { tenant_customer_id.blank? }
  validates :phone, format: { with: /\A(\+1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\z/ }, if: -> { tenant_customer_id.blank? }
  validates :zip, format: { with: /\A\d{5}(-\d{4})?\z/ }, if: -> { tenant_customer_id.blank? }
  validates :total, numericality: { greater_than_or_equal_to: 0 }

  before_validation :calculate_totals
  after_update :convert_to_booking, if: -> { saved_change_to_status? && approved? && deposit_paid? }
  before_create :generate_token

  def deposit_paid?
    deposit_paid_at.present? && approved_at.present? && deposit_paid_at >= approved_at
  end

  def customer_email
    tenant_customer.present? ? tenant_customer.email : email
  end

  private
  def calculate_totals
    self.subtotal = estimate_items.sum { |item| item.qty.to_i * item.cost_rate.to_d }
    self.taxes = estimate_items.sum(&:tax_amount)
    self.total = subtotal + taxes
  end

  def convert_to_booking
    EstimateToBookingService.new(self).call
  end

  def generate_token
    self.token ||= SecureRandom.hex(16)
  end
end
