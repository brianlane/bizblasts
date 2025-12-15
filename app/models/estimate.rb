class Estimate < ApplicationRecord
  include TenantScoped
  acts_as_tenant(:business)

  belongs_to :business
  belongs_to :tenant_customer, optional: true
  belongs_to :booking, optional: true

  has_many :estimate_items, dependent: :destroy
  has_many :estimate_versions, dependent: :destroy
  has_many :estimate_messages, dependent: :destroy

  has_one_attached :pdf # Generated PDF attachment
  has_one :client_document, as: :documentable, dependent: :destroy

  accepts_nested_attributes_for :estimate_items, allow_destroy: true,
    reject_if: ->(attrs) {
      # For labor items, check hours instead of qty
      if attrs['item_type'] == 'labor' || attrs['item_type'] == :labor
        attrs['hours'].to_f <= 0 || attrs['description'].blank?
      else
        attrs['qty'].to_i <= 0 ||
        (attrs['service_id'].blank? && attrs['product_id'].blank? && attrs['description'].blank?)
      end
    }
  accepts_nested_attributes_for :tenant_customer,
    reject_if: ->(attrs) { attrs['first_name'].blank? && attrs['last_name'].blank? && attrs['email'].blank? }

  # Updated enum with pending_payment (approved only after payment succeeds)
  enum :status, {
    draft: 0,
    sent: 1,
    viewed: 2,
    approved: 3,
    declined: 4,
    cancelled: 5,
    pending_payment: 6
  }

  validates :first_name, :last_name, :email, :phone, :address, :city, :state, :zip,
            presence: true, if: -> { tenant_customer_id.blank? }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { tenant_customer_id.blank? }
  validates :phone, format: { with: /\A(\+1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\z/ }, if: -> { tenant_customer_id.blank? }
  validates :zip, format: { with: /\A\d{5}(-\d{4})?\z/ }, if: -> { tenant_customer_id.blank? }
  validates :total, numericality: { greater_than_or_equal_to: 0 }
  validates :valid_for_days, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }
  validates :estimate_number, uniqueness: { scope: :business_id }, allow_nil: true

  before_validation :set_valid_for_days_default, :calculate_totals, :assign_item_positions
  before_create :generate_token, :generate_estimate_number
  after_update :create_version_if_needed, if: :should_version?

  scope :with_optional_items, -> { where(has_optional_items: true) }
  scope :pending_customer_action, -> { where(status: [:sent, :viewed]) }
  scope :awaiting_payment, -> { where(status: :pending_payment) }

  def customer_email
    if tenant_customer.present? && tenant_customer.email.present?
      tenant_customer.email
    else
      email
    end
  end

  def customer_full_name
    if tenant_customer.present?
      "#{tenant_customer.first_name} #{tenant_customer.last_name}".strip
    else
      "#{first_name} #{last_name}".strip
    end
  end

  def customer_phone
    tenant_customer&.phone || phone
  end

  def customer_address
    if tenant_customer.present?
      tenant_customer.address
    else
      address
    end
  end

  def full_address
    [address, city, "#{state} #{zip}"].compact.join(', ')
  end

  def signed?
    signature_data.present? && signed_at.present?
  end

  def requires_signature?
    # All estimates require signature before payment
    true
  end

  def can_approve?
    sent? || viewed?
  end

  def can_decline?
    sent? || viewed? || pending_payment?
  end

  def can_edit?
    draft? || sent? || viewed?
  end

  # Get all items that should be included in totals
  # Non-selected optional items are still kept but marked as declined
  def items_for_calculation
    estimate_items.reject(&:marked_for_destruction?).select do |item|
      !item.customer_declined? && (!item.optional? || item.customer_selected?)
    end
  end

  # Get required items only
  def required_items
    estimate_items.required.by_position
  end

  # Get optional items for customer selection UI
  def optional_items_for_customer
    estimate_items.optional_items.by_position
  end

  # Calculate deposit amount (default to required_deposit or full total if not set)
  def deposit_amount
    required_deposit.present? && required_deposit > 0 ? required_deposit : total
  end

  # Calculate remaining balance after deposit
  def remaining_balance
    total - deposit_amount
  end

  def recalculate_totals!
    calculate_totals
    save!
  end

  def ensure_client_document!
    template = active_template_for('estimate')

    if client_document
      client_document.assign_attributes(
        deposit_amount: deposit_amount,
        payment_required: deposit_amount.to_f.positive?
      )
      apply_template_if_needed(client_document, template)
      client_document.save! if client_document.changed?
      return client_document
    end

    build_client_document(
      business: business,
      tenant_customer: tenant_customer,
      document_type: 'estimate',
      title: "Estimate #{estimate_number || id}",
      deposit_amount: deposit_amount,
      payment_required: deposit_amount.to_f.positive?,
      signature_required: true,
      status: 'pending_signature'
    ).tap do |doc|
      apply_template_if_needed(doc, template)
      doc.save!
      doc.record_event!('created')
    end
  end

  def handle_client_document_payment(document, payment)
    return false if approved?

    invoice_to_update = nil

    transaction do
      update!(
        status: :approved,
        approved_at: Time.current,
        deposit_paid_at: Time.current,
        payment_intent_id: document.payment_intent_id || payment&.stripe_payment_intent_id
      )

      invoice_to_update = document.invoice || booking&.invoice
      invoice_to_update&.update!(status: :paid)
    end

    EstimateMailer.deposit_paid_confirmation(self).deliver_later(queue: 'mailers')
    EstimateMailer.estimate_approved(self).deliver_later(queue: 'mailers')

    true
  end

  private

  def calculate_totals
    # Set totals to 0 if no items exist
    if estimate_items.blank?
      self.subtotal = 0
      self.taxes = 0
      self.total = 0
      self.optional_items_subtotal = 0
      self.optional_items_taxes = 0
      self.has_optional_items = false
      return
    end

    # Filter out items marked for destruction
    items = estimate_items.reject(&:marked_for_destruction?)

    # Set totals to 0 if no valid items remain
    if items.blank?
      self.subtotal = 0
      self.taxes = 0
      self.total = 0
      self.optional_items_subtotal = 0
      self.optional_items_taxes = 0
      self.has_optional_items = false
      return
    end

    # Calculate required items totals
    required_items = items.select { |item| !item.optional? }
    self.subtotal = required_items.sum { |item| item.total.to_d }
    self.taxes = required_items.sum { |item| item.tax_amount.to_d }

    # Calculate optional items totals (for display purposes)
    optional_items = items.select { |item| item.optional? }
    self.has_optional_items = optional_items.any?

    if has_optional_items?
      # Show full optional items potential (before customer selection)
      self.optional_items_subtotal = optional_items.sum { |item| item.total.to_d }
      self.optional_items_taxes = optional_items.sum { |item| item.tax_amount.to_d }

      # Add selected optional items to main totals (not declined ones)
      selected_optional = optional_items.select { |item| item.customer_selected? && !item.customer_declined? }
      self.subtotal += selected_optional.sum { |item| item.total.to_d }
      self.taxes += selected_optional.sum { |item| item.tax_amount.to_d }
    else
      self.optional_items_subtotal = 0
      self.optional_items_taxes = 0
    end

    self.total = (subtotal || 0) + (taxes || 0)
  end

  def active_template_for(document_type)
    business.document_templates.active.for_type(document_type).order(version: :desc).first
  end

  def apply_template_if_needed(document, template)
    return unless template
    return if document.document_template_id == template.id && document.body.present?

    document.apply_template(template)
  end

  def generate_token
    self.token ||= SecureRandom.hex(16)
  end

  def generate_estimate_number
    return if estimate_number.present?

    # Format: EST-YYYYMM-####
    date_prefix = Time.current.strftime('%Y%m')
    last_estimate = business.estimates
      .where("estimate_number LIKE ?", "EST-#{date_prefix}-%")
      .order(estimate_number: :desc)
      .first

    if last_estimate && last_estimate.estimate_number =~ /EST-\d{6}-(\d{4})/
      next_number = $1.to_i + 1
    else
      next_number = 1
    end

    self.estimate_number = "EST-#{date_prefix}-#{next_number.to_s.rjust(4, '0')}"
  end

  # Determine if this estimate update should create a version
  def should_version?
    # Only version if estimate has been sent to customer
    return false unless sent? || viewed? || pending_payment?

    # Don't version if we're just updating version fields
    return false if changes.keys == %w[current_version total_versions]

    # Version if any meaningful fields changed
    versioned_fields = %w[subtotal taxes total has_optional_items
                         optional_items_subtotal optional_items_taxes
                         required_deposit deposit_percentage]

    versioned_fields.any? { |field| saved_change_to_attribute?(field) }
  end

  # Create a version snapshot after update
  def create_version_if_needed
    EstimateVersioningService.create_version(self)
  rescue => e
    Rails.logger.error("Failed to create estimate version: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    # Don't raise - versioning failure shouldn't block estimate updates
  end

  def set_valid_for_days_default
    self.valid_for_days = 30 if valid_for_days.blank?
  end

  # Assign sequential positions to items that don't have proper positions
  # This ensures items created via nested attributes get correct positions
  def assign_item_positions
    return if estimate_items.empty?

    # Find maximum existing position from persisted items
    max_position = estimate_items.select(&:persisted?).map(&:position).compact.max || -1

    # Assign positions to items that have default position (0) or no position
    estimate_items.each do |item|
      next if item.persisted? && item.position > 0 # Skip items with valid positions

      max_position += 1
      item.position = max_position
    end
  end
end
