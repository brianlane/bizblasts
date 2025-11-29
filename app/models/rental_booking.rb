# frozen_string_literal: true

class RentalBooking < ApplicationRecord
  include TenantScoped
  include DurationFormatting
  acts_as_tenant(:business)

  # Enable optimistic locking to prevent concurrent booking conflicts
  self.locking_column = :lock_version

  # Enable audit trail with PaperTrail for compliance and debugging
  # Tracks all changes to rental bookings including who made the change
  #
  # Setup required:
  # 1. Add to Gemfile: gem 'paper_trail'
  # 2. Run: bundle install
  # 3. Run: bundle exec rails generate paper_trail:install
  # 4. Run: bundle exec rails db:migrate
  # 5. Uncomment the line below
  #
  # has_paper_trail on: [:create, :update, :destroy],
  #                 ignore: [:updated_at, :lock_version],
  #                 meta: {
  #                   whodunnit: :paper_trail_originator,
  #                   business_id: :business_id,
  #                   booking_number: :booking_number
  #                 }
  #
  # def paper_trail_originator
  #   # Track who made the change (staff member, customer, or system)
  #   return "Staff: #{staff_member.user.email}" if staff_member.present?
  #   return "Customer: #{tenant_customer.email}" if tenant_customer.present?
  #   "System"
  # end

  # Grace period before assessing late fees (in hours)
  LATE_FEE_GRACE_HOURS = 36

  # ============================================
  # ASSOCIATIONS
  # ============================================
  belongs_to :business
  belongs_to :product  # The rental product
  belongs_to :product_variant, optional: true
  belongs_to :tenant_customer
  belongs_to :staff_member, optional: true
  belongs_to :location, optional: true
  belongs_to :promotion, optional: true
  
  has_many :rental_condition_reports, dependent: :destroy
  has_one :invoice, as: :invoiceable, dependent: :nullify
  has_many :payments, through: :invoice
  
  # ============================================
  # ENUMS
  # ============================================
  enum :status, {
    pending_deposit: 'pending_deposit',   # Awaiting security deposit payment
    deposit_paid: 'deposit_paid',         # Deposit paid, ready for pickup
    checked_out: 'checked_out',           # Item picked up by customer
    overdue: 'overdue',                   # Past return time, not yet returned
    returned: 'returned',                 # Item returned, pending inspection
    completed: 'completed',               # Fully completed, deposit processed
    cancelled: 'cancelled'
  }, prefix: true
  
  enum :deposit_status, {
    pending: 'pending',
    collected: 'collected',
    partial_refund: 'partial_refund',
    full_refund: 'full_refund',
    forfeited: 'forfeited'
  }, prefix: :deposit
  
  # ============================================
  # VALIDATIONS
  # ============================================
  validates :start_time, :end_time, :quantity, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :booking_number, presence: true, uniqueness: { scope: :business_id }
  validates :status, presence: true
  validates :deposit_status, presence: true
  validates :security_deposit_amount,
    numericality: { greater_than_or_equal_to: 0.50, message: "must be at least $0.50 USD for Stripe processing" },
    if: -> { security_deposit_amount.present? && security_deposit_amount > 0 }

  validate :end_time_after_start_time
  validate :rental_product_required
  validate :rental_available_for_period, on: :create
  validate :valid_rental_duration
  
  # ============================================
  # CALLBACKS
  # ============================================
  before_validation :set_booking_number, on: :create
  before_validation :set_guest_access_token, on: :create
  before_validation :calculate_totals, on: :create
  before_validation :set_location_from_product
  
  after_create :send_booking_confirmation
  after_update :handle_status_change, if: :saved_change_to_status?
  
  # ============================================
  # SCOPES
  # ============================================
  scope :upcoming, -> { where('start_time > ?', Time.current).where.not(status: :cancelled) }
  scope :active, -> { where(status: ['deposit_paid', 'checked_out']) }
  scope :needs_return, -> { status_checked_out.where('end_time < ?', Time.current) }
  scope :overdue_rentals, -> { where(status: ['checked_out', 'overdue']).where('end_time < ?', Time.current) }
  scope :pending_pickup, -> { status_deposit_paid.where('start_time <= ?', Time.current) }
  scope :today_returns, -> { status_checked_out.where(end_time: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :today_pickups, -> { status_deposit_paid.where(start_time: Time.current.beginning_of_day..Time.current.end_of_day) }
  
  # ============================================
  # RANSACK
  # ============================================
  def self.ransackable_attributes(auth_object = nil)
    %w[id booking_number status deposit_status start_time end_time quantity total_amount
       security_deposit_amount product_id tenant_customer_id staff_member_id location_id
       business_id created_at updated_at rate_type]
  end
  
  def self.ransackable_associations(auth_object = nil)
    %w[business product product_variant tenant_customer staff_member location promotion 
       rental_condition_reports invoice]
  end
  
  # ============================================
  # INSTANCE METHODS
  # ============================================
  
  # Time zone helpers (consistent with Booking model)
  def local_timezone
    business&.time_zone.presence || Time.zone.name || 'UTC'
  end
  
  def local_start_time
    start_time&.in_time_zone(local_timezone)
  end
  
  def local_end_time
    end_time&.in_time_zone(local_timezone)
  end
  
  # Duration helpers
  def duration_minutes
    return 0 unless start_time && end_time
    ((local_end_time - local_start_time) / 60).ceil
  end
  
  def duration_hours
    (duration_minutes / 60.0).ceil
  end
  
  def duration_days
    (duration_hours / 24.0).ceil
  end
  
  def duration_display
    hours = duration_hours
    if hours < 24
      "#{hours} hour#{'s' if hours != 1}"
    else
      days = duration_days
      "#{days} day#{'s' if days != 1}"
    end
  end
  
  # Status checks
  def overdue?
    status_checked_out? && end_time < Time.current
  end
  
  def can_check_out?
    status_deposit_paid? && start_time <= Time.current
  end
  
  def can_return?
    status_checked_out? || status_overdue?
  end
  
  def can_cancel?
    status_pending_deposit? || status_deposit_paid?
  end
  
  def awaiting_deposit?
    status_pending_deposit?
  end
  
  # Rental item name
  def rental_name
    if product_variant.present? && product_variant.name != 'Default'
      "#{product.name} - #{product_variant.name}"
    else
      product.name
    end
  end
  
  # Customer info helpers
  def customer_full_name
    tenant_customer&.full_name
  end
  
  def customer_email
    tenant_customer&.email
  end
  
  def customer_phone
    tenant_customer&.phone
  end
  
  # ============================================
  # WORKFLOW METHODS
  # ============================================
  
  # Mark deposit as paid (called after Stripe payment succeeds)
  #
  # This method is called by the Stripe webhook handler when a deposit payment
  # is successfully processed. It transitions the booking from pending_deposit
  # to deposit_paid status and sends confirmation notifications.
  #
  # @param payment_intent_id [String, nil] the Stripe PaymentIntent ID
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Called by Stripe webhook
  #   rental_booking.mark_deposit_paid!(payment_intent_id: "pi_123abc")
  #   #=> true
  def mark_deposit_paid!(payment_intent_id: nil)
    return false unless status_pending_deposit?

    transaction do
      update!(
        status: 'deposit_paid',
        deposit_status: :collected,
        deposit_paid_at: Time.current,
        stripe_deposit_payment_intent_id: payment_intent_id
      )

      send_deposit_confirmation
    end
    true
  end

  # Mark deposit as authorized (preauth hold placed)
  #
  # Called when deposit is authorized (held) but not yet captured.
  # Used when business has rental_deposit_preauth_enabled set to true.
  # The funds are held on customer's card but not charged until checkout.
  #
  # @param authorization_id [String] the Stripe PaymentIntent ID
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Called by Stripe webhook for authorized payment
  #   rental_booking.mark_deposit_authorized!(authorization_id: "pi_123abc")
  #   #=> true
  def mark_deposit_authorized!(authorization_id:)
    return false unless status_pending_deposit?

    transaction do
      update!(
        status: 'deposit_paid',  # Status is still "paid" (funds secured)
        deposit_status: :collected,
        deposit_authorization_id: authorization_id,
        deposit_authorized_at: Time.current
      )

      send_deposit_confirmation
    end
    true
  end

  # Capture the authorized deposit (charge the held funds)
  #
  # Captures the previously authorized deposit amount.
  # Called during checkout when business uses preauthorization.
  #
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Capture deposit at checkout
  #   rental_booking.capture_deposit!
  #   #=> true
  def capture_deposit!
    return false unless deposit_authorization_id.present?
    return false if deposit_captured_at.present?

    # Call Stripe to capture the authorized payment
    result = StripeService.capture_rental_deposit_authorization(self)

    if result[:success]
      update!(
        deposit_captured_at: Time.current,
        stripe_deposit_payment_intent_id: deposit_authorization_id
      )
      true
    else
      Rails.logger.error("[RentalBooking] Failed to capture deposit for booking #{booking_number}: #{result[:error]}")
      false
    end
  rescue => e
    Rails.logger.error("[RentalBooking] Error capturing deposit for booking #{booking_number}: #{e.message}")
    false
  end

  # Release the authorized deposit (cancel the hold)
  #
  # Releases the authorization without charging the customer.
  # Called when rental is cancelled before checkout.
  #
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Release authorization on cancellation
  #   rental_booking.release_deposit_authorization!
  #   #=> true
  def release_deposit_authorization!
    return false unless deposit_authorization_id.present?
    return false if deposit_authorization_released_at.present?
    return false if deposit_captured_at.present?  # Can't release if already captured

    # Call Stripe to cancel the authorization
    result = StripeService.cancel_rental_deposit_authorization(self)

    if result[:success]
      update!(deposit_authorization_released_at: Time.current)
      true
    else
      Rails.logger.error("[RentalBooking] Failed to release deposit authorization for booking #{booking_number}: #{result[:error]}")
      false
    end
  rescue => e
    Rails.logger.error("[RentalBooking] Error releasing deposit authorization for booking #{booking_number}: #{e.message}")
    false
  end

  # Check if deposit is using preauthorization (vs immediate capture)
  def using_deposit_preauth?
    business.rental_deposit_preauth_enabled? && deposit_authorization_id.present?
  end

  # Check out the rental (customer picks up)
  #
  # Transitions booking from deposit_paid to checked_out status.
  # Creates a checkout condition report documenting item condition at pickup.
  # Only allowed if deposit is paid and start_time has arrived.
  #
  # @param staff_member [StaffMember] the staff member processing the checkout
  # @param condition_notes [String, nil] optional notes about item condition
  # @param checklist_items [Array<String>] checklist items verified at checkout
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Staff member checking out rental
  #   rental_booking.check_out!(
  #     staff_member: current_staff,
  #     condition_notes: "All items in excellent condition",
  #     checklist_items: ["Battery fully charged", "All accessories included"]
  #   )
  #   #=> true
  def check_out!(staff_member:, condition_notes: nil, checklist_items: [], photos: [])
    return false unless can_check_out?

    success = false

    transaction do
      # If using preauthorization, capture the deposit now
      if using_deposit_preauth? && !deposit_captured_at.present?
        unless capture_deposit!
          Rails.logger.error("[RentalBooking] Failed to capture preauthorized deposit for booking #{booking_number}")
          raise ActiveRecord::Rollback
        end
      end

      report = rental_condition_reports.create!(
        staff_member: staff_member,
        report_type: 'checkout',
        condition_rating: 'good',
        notes: condition_notes,
        checklist_items: checklist_items
      )

      # Attach photos if provided
      report.photos.attach(photos) if photos.present?

      update!(
        status: 'checked_out',
        staff_member: staff_member,
        actual_pickup_time: Time.current,
        condition_notes_checkout: condition_notes
      )

      success = true
    end
    success
  end
  
  # Process return (customer returns item)
  #
  # Transitions booking from checked_out/overdue to returned status.
  # Creates a return condition report documenting item condition.
  # Calculates late fees if returned after end_time.
  # Processes deposit refund (full, partial, or forfeited) based on:
  #   - Late fees (if any)
  #   - Damage fees (if any)
  #
  # @param staff_member [StaffMember] the staff member processing the return
  # @param condition_rating [String] condition rating: 'excellent', 'good', 'fair', 'poor', 'damaged'
  # @param notes [String, nil] optional notes about condition or damage
  # @param damage_amount [Numeric] damage fee amount (deducted from deposit)
  # @param checklist_items [Array<String>] checklist items verified at return
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Processing return with damage
  #   rental_booking.process_return!(
  #     staff_member: current_staff,
  #     condition_rating: 'fair',
  #     notes: "Minor scratch on side panel",
  #     damage_amount: 25.00,
  #     checklist_items: ["All accessories returned"]
  #   )
  #   #=> true
  def process_return!(staff_member:, condition_rating:, notes: nil, damage_amount: 0, checklist_items: [], photos: [])
    return false unless can_return?

    transaction do
      report = rental_condition_reports.create!(
        staff_member: staff_member,
        report_type: 'return',
        condition_rating: condition_rating,
        notes: notes,
        checklist_items: checklist_items,
        damage_assessment_amount: damage_amount,
        damage_description: notes
      )

      # Attach photos if provided (important for damage documentation)
      report.photos.attach(photos) if photos.present?

      update!(
        status: 'returned',
        actual_return_time: Time.current,
        condition_notes_return: notes,
        damage_fee_amount: damage_amount
      )

      # Calculate late fees if applicable
      if late_fee_applicable?
        calculate_late_fees!
      else
        update!(late_fee_amount: nil)
      end

      # Process deposit refund
      process_deposit_refund!
    end
    true
  end
  
  # Complete the rental (after return processing)
  #
  # Transitions booking from returned to completed status.
  # This is the final state - deposit has been processed and rental is done.
  # Sends completion notification to customer.
  #
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Mark rental as completed
  #   rental_booking.complete!
  #   #=> true
  def complete!
    return false unless status_returned?

    update!(status: 'completed')
    send_completion_notification
    true
  end

  # Cancel the rental
  #
  # Cancels the rental booking and processes deposit refund if applicable.
  # Only allowed for bookings in pending_deposit or deposit_paid status.
  # If deposit was already collected, initiates full refund via Stripe.
  # If deposit was preauthorized (held but not captured), releases the authorization.
  #
  # @param reason [String, nil] optional cancellation reason (appended to notes)
  # @return [Boolean] true if successful, false otherwise
  #
  # @example Cancel with reason
  #   rental_booking.cancel!(reason: "Customer request - schedule conflict")
  #   #=> true
  def cancel!(reason: nil)
    return false unless can_cancel?

    transaction do
      # Handle preauthorized deposits (release hold without charging)
      if deposit_authorization_id.present? && !deposit_captured_at.present? && !deposit_authorization_released_at.present?
        unless release_deposit_authorization!
          Rails.logger.error("[RentalBooking] Failed to release deposit authorization for booking #{booking_number}")
          raise ActiveRecord::Rollback
        end

        update!(
          deposit_status: :full_refund,
          deposit_refund_amount: 0  # No charge was made, so nothing to refund
        )
      # Handle captured deposits (refund the charge)
      elsif deposit_collected?
        update!(
          deposit_status: :full_refund,
          deposit_refund_amount: security_deposit_amount
        )
        # Trigger Stripe refund if deposit was paid
        process_stripe_deposit_refund! if stripe_deposit_payment_intent_id.present?
      end

      update!(
        status: 'cancelled',
        notes: [notes, "Cancellation reason: #{reason}"].compact.join("\n")
      )
    end

    send_cancellation_notification
    true
  end
  
  # Mark as overdue
  def mark_overdue!
    return unless status_checked_out? && end_time < Time.current
    update!(status: 'overdue')
    send_overdue_notification
  end
  
  private
  
  # ============================================
  # PRIVATE METHODS
  # ============================================
  
  def set_booking_number
    return if booking_number.present?
    
    loop do
      self.booking_number = "RNT-#{SecureRandom.hex(6).upcase}"
      break unless self.class.exists?(business_id: business_id, booking_number: booking_number)
    end
  end
  
  def set_guest_access_token
    return if guest_access_token.present?
    self.guest_access_token = SecureRandom.urlsafe_base64(32)
  end
  
  def set_location_from_product
    self.location_id ||= product&.location_id
  end
  
  def calculate_totals
    return unless product && start_time && end_time
    return unless quantity.present? && quantity > 0
    
    pricing = product.calculate_rental_price(start_time, end_time, rate_type: rate_type)
    return unless pricing
    
    self.rate_type = pricing[:rate_type]
    self.rate_amount = pricing[:rate]
    self.rate_quantity = pricing[:quantity]
    self.subtotal = pricing[:total] * quantity
    self.security_deposit_amount = (product.security_deposit || 0) * quantity
    
    # Apply promotion discount if present
    if promotion.present?
      self.discount_amount = promotion.calculate_discount(subtotal)
    end
    
    # Calculate tax (using business default tax rate)
    tax_rate = business&.default_tax_rate
    if tax_rate.present?
      taxable_amount = subtotal - (discount_amount || 0)
      self.tax_amount = tax_rate.calculate_tax(taxable_amount)
    end
    
    self.total_amount = subtotal - (discount_amount || 0) + (tax_amount || 0)
  end
  
  def calculate_late_fees!
    return unless business&.rental_late_fee_enabled? && actual_return_time && end_time
    
    late_hours = ((actual_return_time - end_time) / 1.hour).ceil
    late_days = (late_hours / 24.0).ceil
    
    late_fee_rate = business.rental_late_fee_percentage || 15.0
    daily_rate = product&.daily_rate || rate_amount
    
    late_fee = (daily_rate * late_days * (late_fee_rate / 100.0)).round(2)
    update!(late_fee_amount: late_fee)
  end
  
  def was_overdue?
    actual_return_time.present? && actual_return_time > end_time
  end
  
  def late_fee_applicable?
    return false unless business&.rental_late_fee_enabled? && actual_return_time && end_time
    actual_return_time > (end_time + late_fee_grace_period_hours.hours)
  end
  
  def late_fee_grace_period_hours
    value = business.try(:rental_late_fee_grace_hours)
    return value.to_i if value.present? && value.to_i.positive?
    LATE_FEE_GRACE_HOURS
  end
  
  def process_deposit_refund!
    total_deductions = (late_fee_amount || 0) + (damage_fee_amount || 0)
    deposit = security_deposit_amount || 0
    
    if total_deductions >= deposit
      update!(deposit_status: :forfeited, deposit_refund_amount: 0)
    elsif total_deductions > 0
      refund = deposit - total_deductions
      update!(deposit_status: :partial_refund, deposit_refund_amount: refund)
    else
      update!(deposit_status: :full_refund, deposit_refund_amount: deposit)
    end
    
    # Trigger Stripe refund
    process_stripe_deposit_refund! if deposit_refund_amount.to_d > 0 && stripe_deposit_payment_intent_id.present?
  end
  
  def process_stripe_deposit_refund!
    return unless stripe_deposit_payment_intent_id.present? && deposit_refund_amount.to_d > 0
    
    # This will be implemented in StripeService
    StripeService.process_rental_deposit_refund(rental_booking: self)
    update!(deposit_refunded_at: Time.current)
  rescue => e
    Rails.logger.error("[RentalBooking] Failed to process deposit refund for #{booking_number}: #{e.message}")
  end
  
  # ============================================
  # VALIDATIONS
  # ============================================
  
  def end_time_after_start_time
    return unless start_time && end_time
    if end_time <= start_time
      errors.add(:end_time, 'must be after start time')
    end
  end
  
  def rental_product_required
    return unless product
    unless product.rental?
      errors.add(:product, 'must be a rental product')
    end
  end
  
  def rental_available_for_period
    return unless product && start_time && end_time && quantity.present? && quantity > 0
    
    unless product.rental_available_for?(start_time, end_time, quantity: quantity, exclude_booking_id: id)
      errors.add(:base, 'The requested rental is not available for the selected period and quantity')
    end
  end
  
  def valid_rental_duration
    return unless product && start_time && end_time
    
    unless product.valid_rental_duration?(start_time, end_time)
      min_display = product.min_rental_duration_mins ? "minimum #{duration_in_words(product.min_rental_duration_mins)}" : nil
      max_display = product.max_rental_duration_mins ? "maximum #{duration_in_words(product.max_rental_duration_mins)}" : nil
      
      constraint = [min_display, max_display].compact.join(', ')
      errors.add(:base, "Rental duration must be within constraints: #{constraint}")
    end
  end
  
  # ============================================
  # NOTIFICATION METHODS (to be implemented)
  # ============================================
  
  def send_booking_confirmation
    RentalMailer.booking_confirmation(self).deliver_later
    RentalMailer.new_booking_notification(self).deliver_later

    # Send SMS notification if customer is opted in
    SmsService.send_rental_booking_confirmation(self)
  rescue => e
    Rails.logger.error("[RentalBooking] Failed to send booking confirmation: #{e.message}")
  end

  def send_deposit_confirmation
    RentalMailer.deposit_paid_confirmation(self).deliver_later

    # Send SMS notification if customer is opted in
    SmsService.send_rental_deposit_paid(self)
  rescue => e
    Rails.logger.error("[RentalBooking] Failed to send deposit confirmation: #{e.message}")
  end

  def send_overdue_notification
    RentalMailer.overdue_notice(self).deliver_later

    # Send SMS notification if customer is opted in
    SmsService.send_rental_overdue_notice(self)
  rescue => e
    Rails.logger.error("[RentalBooking] Failed to send overdue notification: #{e.message}")
  end

  def send_completion_notification
    RentalMailer.completion_confirmation(self).deliver_later

    # Send SMS notification if customer is opted in
    SmsService.send_rental_completion(self)
  rescue => e
    Rails.logger.error("[RentalBooking] Failed to send completion notification: #{e.message}")
  end

  def send_cancellation_notification
    RentalMailer.cancellation_confirmation(self).deliver_later
  rescue => e
    Rails.logger.error("[RentalBooking] Failed to send cancellation notification: #{e.message}")
  end
  
  def handle_status_change
    # Log status change
    Rails.logger.info("[RentalBooking] #{booking_number} status changed to #{status}")
  end
end

