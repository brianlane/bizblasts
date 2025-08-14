# Tap to Pay on iPhone - Implementation Plan for BizBlasts

## Executive Summary

Enable BizBlasts business users to accept in-person contactless payments directly on their iPhones through the web application, without requiring additional hardware or a separate mobile app. This implementation leverages Stripe's Tap to Pay on iPhone functionality through a Progressive Web App (PWA) approach.

## Prerequisites

### Technical Requirements
- iPhone XS or later
- iOS 16.4 or later
- Stripe account with Tap to Pay on iPhone enabled (requires Stripe approval)
- HTTPS enabled on all payment pages
- Business must have completed Stripe Connect onboarding

### Stripe Requirements
- [ ] Apply for Tap to Pay on iPhone access through Stripe Dashboard
- [ ] Get approval from Stripe (typically 1-2 business days)
- [ ] Enable Terminal API in Stripe Dashboard
- [ ] Configure webhook endpoints for Terminal events

## Implementation Timeline: 3-4 Weeks

## Phase 1: Foundation Setup (Week 1)

### Database Schema Updates

```ruby
# Migration: add_in_person_payment_fields
class AddInPersonPaymentFields < ActiveRecord::Migration[7.0]
  def change
    # Track quick sales for in-person transactions
    create_table :quick_sales do |t|
      t.references :business, null: false, foreign_key: true
      t.references :tenant_customer, foreign_key: true
      t.references :payment, foreign_key: true
      t.references :order, foreign_key: true
      t.string :description
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :tip_amount, precision: 10, scale: 2, default: 0
      t.integer :payment_type, default: 0 # enum: product, service, tip, custom
      t.integer :status, default: 0 # enum: pending, completed, failed, cancelled
      t.string :stripe_payment_intent_id
      t.string :stripe_terminal_payment_id
      t.jsonb :metadata
      t.timestamps
    end

    # Track Terminal/Tap to Pay readers
    create_table :terminal_readers do |t|
      t.references :business, null: false, foreign_key: true
      t.string :stripe_reader_id
      t.string :reader_type # 'tap_to_pay', 'physical_reader'
      t.string :label
      t.string :device_type # 'iPhone', 'iPad'
      t.string :device_model
      t.string :ios_version
      t.integer :status, default: 0 # enum: online, offline, in_use
      t.datetime :last_seen_at
      t.jsonb :capabilities
      t.timestamps
    end

    # Update payments table
    add_column :payments, :payment_collection_method, :string, default: 'online'
    # Values: 'online', 'tap_to_pay', 'terminal', 'cash'
    add_column :payments, :collected_by_user_id, :bigint
    add_column :payments, :terminal_reader_id, :bigint
    add_column :payments, :quick_sale_id, :bigint
    
    # Track payment collection sessions
    create_table :payment_collection_sessions do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.references :quick_sale, foreign_key: true
      t.string :stripe_payment_intent_id
      t.string :stripe_reader_id
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :status, default: 0 # enum: active, completed, failed, cancelled
      t.datetime :expires_at
      t.jsonb :metadata
      t.timestamps
    end

    add_index :quick_sales, :stripe_payment_intent_id
    add_index :terminal_readers, :stripe_reader_id
    add_index :payment_collection_sessions, :stripe_payment_intent_id
  end
end
```

### Model Creation

#### app/models/quick_sale.rb
```ruby
class QuickSale < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :tenant_customer, optional: true
  belongs_to :payment, optional: true
  belongs_to :order, optional: true
  
  enum payment_type: {
    product: 0,
    service: 1,
    tip: 2,
    custom: 3
  }
  
  enum status: {
    pending: 0,
    completed: 1,
    failed: 2,
    cancelled: 3
  }
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
  
  scope :today, -> { where(created_at: Date.current.all_day) }
  scope :completed, -> { where(status: 'completed') }
  
  def total_amount
    amount + (tip_amount || 0)
  end
  
  def display_description
    description.presence || "Quick Sale ##{id}"
  end
end
```

#### app/models/terminal_reader.rb
```ruby
class TerminalReader < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  has_many :payments
  
  enum status: {
    online: 0,
    offline: 1,
    in_use: 2
  }
  
  enum reader_type: {
    tap_to_pay: 0,
    physical_reader: 1
  }
  
  validates :stripe_reader_id, presence: true, uniqueness: true
  validates :label, presence: true
  
  scope :available, -> { where(status: 'online') }
  scope :tap_to_pay_readers, -> { where(reader_type: 'tap_to_pay') }
  
  def display_name
    "#{label} (#{device_model})"
  end
  
  def online?
    last_seen_at && last_seen_at > 5.minutes.ago
  end
  
  def mark_online!
    update!(status: 'online', last_seen_at: Time.current)
  end
  
  def mark_offline!
    update!(status: 'offline')
  end
end
```

#### app/models/payment_collection_session.rb
```ruby
class PaymentCollectionSession < ApplicationRecord
  include TenantScoped
  
  belongs_to :business
  belongs_to :user
  belongs_to :order, optional: true
  belongs_to :quick_sale, optional: true
  
  enum status: {
    active: 0,
    completed: 1,
    failed: 2,
    cancelled: 3
  }
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :expires_at, presence: true
  
  scope :active, -> { where(status: 'active').where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  
  before_validation :set_expiration, on: :create
  
  def expired?
    expires_at <= Time.current
  end
  
  def cancel!
    update!(status: 'cancelled')
  end
  
  private
  
  def set_expiration
    self.expires_at ||= 5.minutes.from_now
  end
end
```

## Phase 2: Stripe Terminal Service Integration (Week 1-2)

### app/services/stripe_tap_to_pay_service.rb
```ruby
class StripeTapToPayService
  class << self
    def configure_stripe_api_key
      Stripe.api_key = ENV.fetch('STRIPE_SECRET_KEY')
    end

    # Create a connection token for Terminal SDK initialization
    def create_connection_token(business)
      configure_stripe_api_key
      
      token = Stripe::Terminal::ConnectionToken.create(
        {
          location: get_or_create_location(business)
        },
        {
          stripe_account: business.stripe_account_id
        }
      )
      
      token.secret
    rescue Stripe::StripeError => e
      Rails.logger.error "[TAP_TO_PAY] Connection token creation failed: #{e.message}"
      raise
    end

    # Register a simulated reader for Tap to Pay
    def register_tap_to_pay_reader(business:, user:, device_info:)
      configure_stripe_api_key
      
      # Create or update reader record
      reader = business.terminal_readers.find_or_initialize_by(
        device_type: device_info[:device_type],
        device_model: device_info[:device_model],
        label: "#{user.name}'s #{device_info[:device_model]}"
      )
      
      # Register with Stripe Terminal
      stripe_reader = Stripe::Terminal::Reader.create(
        {
          registration_code: 'simulated-reader-tap-to-pay',
          label: reader.label,
          location: get_or_create_location(business),
          metadata: {
            business_id: business.id,
            user_id: user.id,
            device_info: device_info.to_json
          }
        },
        {
          stripe_account: business.stripe_account_id
        }
      )
      
      reader.update!(
        stripe_reader_id: stripe_reader.id,
        reader_type: 'tap_to_pay',
        ios_version: device_info[:ios_version],
        capabilities: stripe_reader.device_type,
        status: 'online',
        last_seen_at: Time.current
      )
      
      reader
    rescue Stripe::StripeError => e
      Rails.logger.error "[TAP_TO_PAY] Reader registration failed: #{e.message}"
      raise
    end

    # Create a payment intent for Terminal collection
    def create_terminal_payment_intent(amount:, business:, description: nil, metadata: {})
      configure_stripe_api_key
      
      amount_cents = (amount * 100).to_i
      platform_fee_cents = StripeService.calculate_platform_fee_cents(amount_cents, business)
      
      intent = Stripe::PaymentIntent.create(
        {
          amount: amount_cents,
          currency: 'usd',
          payment_method_types: ['card_present'],
          capture_method: 'automatic',
          description: description,
          metadata: metadata.merge(
            business_id: business.id,
            collection_method: 'tap_to_pay'
          ),
          application_fee_amount: platform_fee_cents
        },
        {
          stripe_account: business.stripe_account_id
        }
      )
      
      intent
    rescue Stripe::StripeError => e
      Rails.logger.error "[TAP_TO_PAY] Payment intent creation failed: #{e.message}"
      raise
    end

    # Process payment collection result
    def process_payment_result(payment_intent_id:, business:, user:, quick_sale: nil, order: nil)
      configure_stripe_api_key
      
      intent = Stripe::PaymentIntent.retrieve(
        payment_intent_id,
        { stripe_account: business.stripe_account_id }
      )
      
      if intent.status == 'succeeded'
        # Create payment record
        payment = create_payment_record(intent, business, user, quick_sale, order)
        
        # Update quick sale or order status
        quick_sale&.update!(status: 'completed', payment: payment)
        order&.update!(status: 'paid')
        
        # Send receipt
        send_receipt(payment, intent)
        
        { success: true, payment: payment }
      else
        { success: false, error: "Payment #{intent.status}: #{intent.last_payment_error&.message}" }
      end
    rescue Stripe::StripeError => e
      Rails.logger.error "[TAP_TO_PAY] Payment processing failed: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def get_or_create_location(business)
      @location_cache ||= {}
      
      return @location_cache[business.id] if @location_cache[business.id]
      
      # Check if location exists
      locations = Stripe::Terminal::Location.list(
        { limit: 100 },
        { stripe_account: business.stripe_account_id }
      )
      
      location = locations.data.find { |l| l.metadata['business_id'] == business.id.to_s }
      
      # Create if doesn't exist
      unless location
        location = Stripe::Terminal::Location.create(
          {
            display_name: business.name,
            address: {
              line1: business.address || '123 Main St',
              city: business.city || 'Phoenix',
              state: business.state || 'AZ',
              country: 'US',
              postal_code: business.zip || '85001'
            },
            metadata: { business_id: business.id }
          },
          {
            stripe_account: business.stripe_account_id
          }
        )
      end
      
      @location_cache[business.id] = location.id
      location.id
    end

    def create_payment_record(intent, business, user, quick_sale, order)
      tenant_customer = quick_sale&.tenant_customer || order&.tenant_customer
      
      amount = intent.amount / 100.0
      platform_fee = intent.application_fee_amount / 100.0
      stripe_fee = StripeService.calculate_stripe_fee_cents(intent.amount) / 100.0
      business_amount = amount - platform_fee - stripe_fee
      
      Payment.create!(
        business: business,
        tenant_customer: tenant_customer,
        order: order,
        quick_sale: quick_sale,
        amount: amount,
        stripe_payment_intent_id: intent.id,
        payment_method: 'credit_card',
        payment_collection_method: 'tap_to_pay',
        collected_by_user_id: user.id,
        status: 'completed',
        stripe_fee_amount: stripe_fee,
        platform_fee_amount: platform_fee,
        business_amount: business_amount,
        paid_at: Time.current
      )
    end

    def send_receipt(payment, intent)
      # Send email receipt if customer email available
      if payment.tenant_customer&.email.present?
        PaymentMailer.tap_to_pay_receipt(payment).deliver_later
      end
    end
  end
end
```

## Phase 3: Controllers & Routes (Week 2)

### config/routes.rb additions
```ruby
namespace :business_manager do
  # In-person payment routes
  namespace :pos do  # Point of Sale
    get '/', to: 'dashboard#index', as: :dashboard
    
    resources :quick_sales, only: [:new, :create] do
      member do
        get :collect_payment
        post :process_payment
        get :receipt
      end
    end
    
    namespace :tap_to_pay do
      get :setup
      post :register_reader
      post :create_connection_token
      post :create_payment_intent
      post :process_payment
      get :status
    end
  end
  
  # Add tap to pay to existing orders
  resources :orders do
    member do
      get :tap_to_pay_collection
      post :process_tap_payment
    end
  end
end
```

### app/controllers/business_manager/pos/dashboard_controller.rb
```ruby
module BusinessManager
  module Pos
    class DashboardController < BusinessManager::BaseController
      before_action :check_ios_compatibility
      before_action :check_stripe_setup
      
      def index
        @today_sales = current_business.quick_sales.today.completed
        @pending_orders = current_business.orders.status_pending_payment.limit(5)
        @recent_payments = current_business.payments
                                          .where(payment_collection_method: 'tap_to_pay')
                                          .order(created_at: :desc)
                                          .limit(10)
        
        @reader_status = check_reader_status
        @can_use_tap_to_pay = ios_tap_to_pay_capable?
      end
      
      private
      
      def check_ios_compatibility
        unless request.user_agent&.match?(/iPhone|iPad/)
          flash[:alert] = "Tap to Pay requires an iPhone or iPad"
          redirect_to business_manager_dashboard_path
        end
      end
      
      def check_stripe_setup
        unless current_business.stripe_account_id.present?
          flash[:alert] = "Please complete Stripe setup first"
          redirect_to edit_business_manager_settings_business_path
        end
      end
      
      def check_reader_status
        reader = current_business.terminal_readers.tap_to_pay_readers.first
        return 'not_registered' unless reader
        
        reader.online? ? 'online' : 'offline'
      end
      
      def ios_tap_to_pay_capable?
        # Check if device is iPhone XS or later with iOS 16.4+
        user_agent = request.user_agent || ''
        
        # Extract iOS version
        ios_match = user_agent.match(/OS (\d+)_(\d+)/)
        return false unless ios_match
        
        ios_major = ios_match[1].to_i
        ios_minor = ios_match[2].to_i
        
        # Check iOS version (16.4 or later)
        return false if ios_major < 16 || (ios_major == 16 && ios_minor < 4)
        
        # Check iPhone model (XS or later)
        # This is a simplified check - in production, use a more robust detection
        model_compatible = user_agent.match?(/iPhone1[1-9]|iPhone[2-9]\d/)
        
        model_compatible
      end
    end
  end
end
```

### app/controllers/business_manager/pos/tap_to_pay_controller.rb
```ruby
module BusinessManager
  module Pos
    class TapToPayController < BusinessManager::BaseController
      before_action :ensure_ios_device
      before_action :ensure_stripe_connected
      skip_before_action :verify_authenticity_token, only: [:create_connection_token, :process_payment]
      
      def setup
        @reader = current_business.terminal_readers.tap_to_pay_readers.first
        @device_info = extract_device_info
      end
      
      def register_reader
        device_info = {
          device_type: params[:device_type],
          device_model: params[:device_model],
          ios_version: params[:ios_version]
        }
        
        reader = StripeTapToPayService.register_tap_to_pay_reader(
          business: current_business,
          user: current_user,
          device_info: device_info
        )
        
        render json: { 
          success: true, 
          reader_id: reader.stripe_reader_id,
          message: "Reader registered successfully"
        }
      rescue => e
        render json: { success: false, error: e.message }, status: :unprocessable_entity
      end
      
      def create_connection_token
        token = StripeTapToPayService.create_connection_token(current_business)
        render json: { secret: token }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
      
      def create_payment_intent
        quick_sale = nil
        order = nil
        
        if params[:quick_sale_id].present?
          quick_sale = current_business.quick_sales.find(params[:quick_sale_id])
          amount = quick_sale.total_amount
          description = quick_sale.display_description
        elsif params[:order_id].present?
          order = current_business.orders.find(params[:order_id])
          amount = order.total_amount
          description = "Order ##{order.order_number}"
        else
          amount = params[:amount].to_f
          description = params[:description] || "In-person payment"
        end
        
        intent = StripeTapToPayService.create_terminal_payment_intent(
          amount: amount,
          business: current_business,
          description: description,
          metadata: {
            user_id: current_user.id,
            quick_sale_id: quick_sale&.id,
            order_id: order&.id
          }
        )
        
        # Create payment collection session
        session = current_business.payment_collection_sessions.create!(
          user: current_user,
          quick_sale: quick_sale,
          order: order,
          stripe_payment_intent_id: intent.id,
          amount: amount,
          metadata: { description: description }
        )
        
        render json: { 
          payment_intent: intent.id,
          client_secret: intent.client_secret,
          session_id: session.id
        }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
      
      def process_payment
        session = current_business.payment_collection_sessions.find(params[:session_id])
        
        result = StripeTapToPayService.process_payment_result(
          payment_intent_id: params[:payment_intent_id],
          business: current_business,
          user: current_user,
          quick_sale: session.quick_sale,
          order: session.order
        )
        
        if result[:success]
          session.update!(status: 'completed')
          render json: { 
            success: true, 
            payment_id: result[:payment].id,
            receipt_url: receipt_path(result[:payment])
          }
        else
          session.update!(status: 'failed')
          render json: { success: false, error: result[:error] }, status: :unprocessable_entity
        end
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
      
      private
      
      def ensure_ios_device
        unless request.user_agent&.match?(/iPhone|iPad/)
          render json: { error: "Tap to Pay requires iOS device" }, status: :forbidden
        end
      end
      
      def ensure_stripe_connected
        unless current_business.stripe_account_id.present?
          render json: { error: "Stripe not connected" }, status: :forbidden
        end
      end
      
      def extract_device_info
        user_agent = request.user_agent || ''
        
        {
          device_type: user_agent.match?(/iPad/) ? 'iPad' : 'iPhone',
          device_model: extract_model(user_agent),
          ios_version: extract_ios_version(user_agent)
        }
      end
      
      def extract_model(user_agent)
        # Extract device model from user agent
        # This is simplified - use a proper library in production
        case user_agent
        when /iPhone14,/ then "iPhone 14"
        when /iPhone13,/ then "iPhone 13"
        when /iPhone12,/ then "iPhone 12"
        when /iPhone11,/ then "iPhone 11"
        when /iPhone10,[3,6]/ then "iPhone XS"
        else "iPhone"
        end
      end
      
      def extract_ios_version(user_agent)
        match = user_agent.match(/OS (\d+_\d+)/)
        match ? match[1].gsub('_', '.') : 'Unknown'
      end
    end
  end
end
```

## Phase 4: JavaScript Implementation (Week 2-3)

### app/javascript/controllers/tap_to_pay_controller.js
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "amount", "payButton", "cancelButton", "receipt"]
  static values = { 
    connectionTokenUrl: String,
    createIntentUrl: String,
    processPaymentUrl: String,
    amount: Number,
    quickSaleId: Number,
    orderId: Number
  }
  
  terminal = null
  paymentIntentId = null
  sessionId = null
  discoveredReaders = []
  connectedReader = null
  
  async connect() {
    // Check if running on iOS Safari
    if (!this.isIOSSafari()) {
      this.showError("Tap to Pay requires Safari on iPhone")
      return
    }
    
    // Check if Stripe Terminal SDK is available
    if (typeof StripeTerminal === 'undefined') {
      this.showError("Stripe Terminal SDK not loaded")
      return
    }
    
    await this.initializeTerminal()
  }
  
  async initializeTerminal() {
    try {
      this.updateStatus("Initializing...")
      
      // Create Terminal instance
      this.terminal = StripeTerminal.create({
        onFetchConnectionToken: this.fetchConnectionToken.bind(this),
        onUnexpectedReaderDisconnect: this.handleUnexpectedDisconnect.bind(this),
        onConnectionStatusChange: this.handleConnectionStatusChange.bind(this),
      })
      
      // Discover readers
      await this.discoverReaders()
      
    } catch (error) {
      console.error("Terminal initialization failed:", error)
      this.showError("Failed to initialize: " + error.message)
    }
  }
  
  async fetchConnectionToken() {
    const response = await fetch(this.connectionTokenUrlValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    
    const data = await response.json()
    return data.secret
  }
  
  async discoverReaders() {
    this.updateStatus("Looking for Tap to Pay...")
    
    const discoverResult = await this.terminal.discoverReaders({
      simulated: false,
      location: null,
      discoveryMethod: 'localMobile' // For Tap to Pay
    })
    
    if (discoverResult.error) {
      this.showError("Failed to discover readers: " + discoverResult.error.message)
      return
    }
    
    this.discoveredReaders = discoverResult.discoveredReaders
    
    if (this.discoveredReaders.length === 0) {
      // No readers found, need to register
      await this.registerReader()
    } else {
      // Connect to first available reader
      await this.connectToReader(this.discoveredReaders[0])
    }
  }
  
  async registerReader() {
    this.updateStatus("Registering device...")
    
    // Get device info
    const deviceInfo = {
      device_type: this.getDeviceType(),
      device_model: this.getDeviceModel(),
      ios_version: this.getIOSVersion()
    }
    
    // Register with backend
    const response = await fetch('/manage/pos/tap_to_pay/register_reader', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify(deviceInfo)
    })
    
    const result = await response.json()
    
    if (result.success) {
      // Try discovering again after registration
      await this.discoverReaders()
    } else {
      this.showError("Registration failed: " + result.error)
    }
  }
  
  async connectToReader(reader) {
    this.updateStatus("Connecting to reader...")
    
    const connectResult = await this.terminal.connectReader(reader, {
      locationId: reader.location
    })
    
    if (connectResult.error) {
      this.showError("Failed to connect: " + connectResult.error.message)
      return
    }
    
    this.connectedReader = connectResult.reader
    this.updateStatus("Ready to accept payment")
    this.payButtonTarget.disabled = false
  }
  
  async collectPayment() {
    if (!this.connectedReader) {
      this.showError("No reader connected")
      return
    }
    
    this.payButtonTarget.disabled = true
    this.cancelButtonTarget.hidden = false
    
    try {
      // Create payment intent
      this.updateStatus("Creating payment...")
      const intentResponse = await fetch(this.createIntentUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          amount: this.amountValue,
          quick_sale_id: this.quickSaleIdValue,
          order_id: this.orderIdValue,
          description: this.data.get("description")
        })
      })
      
      const intentData = await intentResponse.json()
      if (intentData.error) {
        throw new Error(intentData.error)
      }
      
      this.paymentIntentId = intentData.payment_intent
      this.sessionId = intentData.session_id
      
      // Collect payment
      this.updateStatus("Tap card on back of phone...")
      const result = await this.terminal.collectPaymentMethod(
        intentData.client_secret,
        {
          configOverride: {
            skipTipping: false, // Allow tipping
            updatePaymentIntent: true
          }
        }
      )
      
      if (result.error) {
        throw new Error(result.error.message)
      }
      
      // Process payment
      this.updateStatus("Processing payment...")
      const processResult = await this.terminal.processPayment(result.paymentIntent)
      
      if (processResult.error) {
        throw new Error(processResult.error.message)
      }
      
      // Confirm with backend
      await this.confirmPayment(processResult.paymentIntent)
      
    } catch (error) {
      console.error("Payment collection failed:", error)
      this.showError("Payment failed: " + error.message)
      this.payButtonTarget.disabled = false
    } finally {
      this.cancelButtonTarget.hidden = true
    }
  }
  
  async confirmPayment(paymentIntent) {
    this.updateStatus("Confirming payment...")
    
    const response = await fetch(this.processPaymentUrlValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        payment_intent_id: paymentIntent.id,
        session_id: this.sessionId
      })
    })
    
    const result = await response.json()
    
    if (result.success) {
      this.showSuccess("Payment successful!")
      this.showReceipt(result.receipt_url)
      
      // Reset for next payment
      setTimeout(() => {
        this.resetForNextPayment()
      }, 3000)
    } else {
      throw new Error(result.error)
    }
  }
  
  async cancelPayment() {
    if (this.paymentIntentId) {
      await this.terminal.cancelCollectPaymentMethod()
      this.updateStatus("Payment cancelled")
      this.paymentIntentId = null
      this.sessionId = null
    }
    
    this.payButtonTarget.disabled = false
    this.cancelButtonTarget.hidden = true
  }
  
  resetForNextPayment() {
    this.paymentIntentId = null
    this.sessionId = null
    this.payButtonTarget.disabled = false
    this.cancelButtonTarget.hidden = true
    this.updateStatus("Ready for next payment")
    this.receiptTarget.hidden = true
  }
  
  // Status and error handling
  updateStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.className = "status-message"
    }
  }
  
  showError(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.className = "status-message error"
    }
  }
  
  showSuccess(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.className = "status-message success"
    }
  }
  
  showReceipt(url) {
    if (this.hasReceiptTarget) {
      this.receiptTarget.innerHTML = `
        <a href="${url}" target="_blank" class="btn btn-primary">
          View Receipt
        </a>
      `
      this.receiptTarget.hidden = false
    }
  }
  
  // Event handlers
  handleUnexpectedDisconnect() {
    this.showError("Reader disconnected unexpectedly")
    this.connectedReader = null
    this.payButtonTarget.disabled = true
    
    // Try to reconnect
    setTimeout(() => {
      this.discoverReaders()
    }, 2000)
  }
  
  handleConnectionStatusChange(event) {
    console.log("Connection status changed:", event)
    
    if (event.status === 'not_connected') {
      this.updateStatus("Reader disconnected")
      this.payButtonTarget.disabled = true
    }
  }
  
  // Device detection helpers
  isIOSSafari() {
    const ua = navigator.userAgent
    const iOS = /iPad|iPhone|iPod/.test(ua) && !window.MSStream
    const safari = /Safari/.test(ua) && !/Chrome/.test(ua)
    return iOS && safari
  }
  
  getDeviceType() {
    return /iPad/.test(navigator.userAgent) ? 'iPad' : 'iPhone'
  }
  
  getDeviceModel() {
    // Simplified model detection
    const ua = navigator.userAgent
    if (ua.includes('iPhone14,')) return 'iPhone 14'
    if (ua.includes('iPhone13,')) return 'iPhone 13'
    if (ua.includes('iPhone12,')) return 'iPhone 12'
    if (ua.includes('iPhone11,')) return 'iPhone 11'
    return 'iPhone'
  }
  
  getIOSVersion() {
    const match = navigator.userAgent.match(/OS (\d+)_(\d+)/)
    return match ? `${match[1]}.${match[2]}` : 'Unknown'
  }
  
  disconnect() {
    if (this.terminal) {
      this.terminal.disconnectReader()
      this.terminal = null
    }
  }
}
```

## Phase 5: Views & UI (Week 3)

### app/views/business_manager/pos/dashboard/index.html.erb
```erb
<div class="pos-dashboard" data-turbo-permanent>
  <div class="pos-header">
    <h1>Point of Sale</h1>
    <div class="reader-status">
      <% if @can_use_tap_to_pay %>
        <span class="status-indicator <%= @reader_status %>"></span>
        <%= @reader_status.humanize %>
      <% else %>
        <span class="status-indicator incompatible"></span>
        Device not compatible
      <% end %>
    </div>
  </div>

  <% if @can_use_tap_to_pay %>
    <div class="quick-actions">
      <%= link_to new_business_manager_pos_quick_sale_path, 
                  class: "btn btn-primary btn-lg", 
                  data: { turbo_frame: "payment_modal" } do %>
        <i class="fas fa-dollar-sign"></i>
        Quick Sale
      <% end %>
      
      <%= link_to business_manager_orders_path(status: 'pending_payment'), 
                  class: "btn btn-secondary btn-lg" do %>
        <i class="fas fa-file-invoice"></i>
        Pending Orders
      <% end %>
    </div>

    <div class="today-summary">
      <h2>Today's Sales</h2>
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-value">
            <%= number_to_currency(@today_sales.sum(&:total_amount)) %>
          </div>
          <div class="stat-label">Total Sales</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">
            <%= @today_sales.count %>
          </div>
          <div class="stat-label">Transactions</div>
        </div>
      </div>
    </div>

    <% if @pending_orders.any? %>
      <div class="pending-orders">
        <h2>Pending Orders</h2>
        <div class="order-list">
          <% @pending_orders.each do |order| %>
            <div class="order-item">
              <div class="order-info">
                <strong><%= order.order_number %></strong>
                <span><%= order.tenant_customer&.full_name %></span>
              </div>
              <div class="order-amount">
                <%= number_to_currency(order.total_amount) %>
              </div>
              <%= link_to "Collect Payment", 
                          tap_to_pay_collection_business_manager_order_path(order),
                          class: "btn btn-sm btn-primary" %>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <div class="recent-transactions">
      <h2>Recent Tap to Pay Transactions</h2>
      <% if @recent_payments.any? %>
        <table class="table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Description</th>
              <th>Amount</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <% @recent_payments.each do |payment| %>
              <tr>
                <td><%= payment.created_at.strftime("%l:%M %p") %></td>
                <td>
                  <%= payment.quick_sale&.description || 
                      "Order ##{payment.order&.order_number}" %>
                </td>
                <td><%= number_to_currency(payment.amount) %></td>
                <td>
                  <span class="badge badge-<%= payment.status %>">
                    <%= payment.status.humanize %>
                  </span>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% else %>
        <p class="text-muted">No transactions yet today</p>
      <% end %>
    </div>
  <% else %>
    <div class="incompatible-device">
      <i class="fas fa-exclamation-triangle"></i>
      <h2>Device Not Compatible</h2>
      <p>
        Tap to Pay requires an iPhone XS or later running iOS 16.4 or higher.
        Please use a compatible device to accept in-person payments.
      </p>
      <p class="device-info">
        Your device: <%= @device_info[:device_model] %> 
        (iOS <%= @device_info[:ios_version] %>)
      </p>
    </div>
  <% end %>
</div>

<%= turbo_frame_tag "payment_modal" %>
```

### app/views/business_manager/pos/quick_sales/new.html.erb
```erb
<%= turbo_frame_tag "payment_modal" do %>
  <div class="modal show" style="display: block;">
    <div class="modal-dialog modal-lg">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title">Quick Sale</h5>
          <%= link_to "×", business_manager_pos_dashboard_path, 
                      class: "close", 
                      data: { turbo_frame: "_top" } %>
        </div>
        
        <%= form_with model: @quick_sale, 
                     url: business_manager_pos_quick_sales_path,
                     local: false do |f| %>
          <div class="modal-body">
            <div class="form-group">
              <%= f.label :amount, "Amount" %>
              <div class="input-group">
                <div class="input-group-prepend">
                  <span class="input-group-text">$</span>
                </div>
                <%= f.number_field :amount, 
                                  class: "form-control form-control-lg", 
                                  step: 0.01, 
                                  min: 0.50,
                                  required: true,
                                  autofocus: true,
                                  placeholder: "0.00" %>
              </div>
            </div>
            
            <div class="form-group">
              <%= f.label :description %>
              <%= f.text_field :description, 
                             class: "form-control",
                             placeholder: "What is this payment for?" %>
            </div>
            
            <div class="form-group">
              <%= f.label :payment_type %>
              <%= f.select :payment_type, 
                         options_for_select([
                           ['Product', 'product'],
                           ['Service', 'service'],
                           ['Custom', 'custom']
                         ]),
                         {},
                         class: "form-control" %>
            </div>
            
            <div class="form-group">
              <%= f.label :tenant_customer_id, "Customer (Optional)" %>
              <%= f.select :tenant_customer_id,
                         options_from_collection_for_select(
                           current_business.tenant_customers.order(:first_name),
                           :id,
                           :full_name
                         ),
                         { include_blank: "Walk-in Customer" },
                         class: "form-control" %>
            </div>
            
            <div class="form-check">
              <%= check_box_tag :add_tip, "1", false, class: "form-check-input" %>
              <%= label_tag :add_tip, "Allow customer to add tip", 
                          class: "form-check-label" %>
            </div>
          </div>
          
          <div class="modal-footer">
            <%= link_to "Cancel", 
                       business_manager_pos_dashboard_path,
                       class: "btn btn-secondary",
                       data: { turbo_frame: "_top" } %>
            <%= f.submit "Proceed to Payment", 
                        class: "btn btn-primary",
                        data: { disable_with: "Processing..." } %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

### app/views/business_manager/pos/quick_sales/collect_payment.html.erb
```erb
<div class="tap-to-pay-container" 
     data-controller="tap-to-pay"
     data-tap-to-pay-connection-token-url-value="<%= business_manager_pos_tap_to_pay_create_connection_token_path %>"
     data-tap-to-pay-create-intent-url-value="<%= business_manager_pos_tap_to_pay_create_payment_intent_path %>"
     data-tap-to-pay-process-payment-url-value="<%= business_manager_pos_tap_to_pay_process_payment_path %>"
     data-tap-to-pay-amount-value="<%= @quick_sale.total_amount %>"
     data-tap-to-pay-quick-sale-id-value="<%= @quick_sale.id %>"
     data-description="<%= @quick_sale.display_description %>">
  
  <div class="payment-header">
    <%= link_to business_manager_pos_dashboard_path, class: "back-link" do %>
      <i class="fas fa-arrow-left"></i> Back
    <% end %>
  </div>
  
  <div class="payment-amount-display">
    <div class="amount-label">Amount Due</div>
    <div class="amount-value" data-tap-to-pay-target="amount">
      <%= number_to_currency(@quick_sale.total_amount) %>
    </div>
    <div class="description"><%= @quick_sale.display_description %></div>
  </div>
  
  <div class="payment-status" data-tap-to-pay-target="status">
    Initializing payment system...
  </div>
  
  <div class="payment-actions">
    <button class="btn btn-primary btn-lg btn-block" 
            data-tap-to-pay-target="payButton"
            data-action="click->tap-to-pay#collectPayment"
            disabled>
      <i class="fas fa-credit-card"></i>
      Tap to Pay
    </button>
    
    <button class="btn btn-danger btn-lg btn-block" 
            data-tap-to-pay-target="cancelButton"
            data-action="click->tap-to-pay#cancelPayment"
            hidden>
      Cancel Payment
    </button>
  </div>
  
  <div class="payment-instructions">
    <div class="instruction-card">
      <h4>How to accept payment:</h4>
      <ol>
        <li>Tap the "Tap to Pay" button above</li>
        <li>Ask customer to tap their card on the back of your iPhone</li>
        <li>Hold the card steady until payment completes</li>
      </ol>
    </div>
    
    <div class="accepted-cards">
      <p>Accepts:</p>
      <div class="card-logos">
        <i class="fab fa-cc-visa"></i>
        <i class="fab fa-cc-mastercard"></i>
        <i class="fab fa-cc-amex"></i>
        <i class="fab fa-cc-discover"></i>
        <i class="fab fa-apple-pay"></i>
        <i class="fab fa-google-pay"></i>
      </div>
    </div>
  </div>
  
  <div class="receipt-section" data-tap-to-pay-target="receipt" hidden>
    <!-- Receipt link will be inserted here -->
  </div>
</div>

<style>
  .tap-to-pay-container {
    max-width: 500px;
    margin: 0 auto;
    padding: 20px;
  }
  
  .payment-amount-display {
    text-align: center;
    margin: 40px 0;
  }
  
  .amount-label {
    font-size: 14px;
    color: #666;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  
  .amount-value {
    font-size: 48px;
    font-weight: bold;
    color: #333;
    margin: 10px 0;
  }
  
  .payment-status {
    text-align: center;
    padding: 15px;
    margin: 20px 0;
    border-radius: 8px;
    background: #f8f9fa;
  }
  
  .payment-status.error {
    background: #f8d7da;
    color: #721c24;
  }
  
  .payment-status.success {
    background: #d4edda;
    color: #155724;
  }
  
  .instruction-card {
    background: #f8f9fa;
    padding: 20px;
    border-radius: 8px;
    margin: 30px 0;
  }
  
  .accepted-cards {
    text-align: center;
    margin-top: 20px;
  }
  
  .card-logos {
    display: flex;
    justify-content: center;
    gap: 15px;
    font-size: 32px;
    color: #666;
  }
</style>
```

## Phase 6: Testing Strategy (Week 3-4)

### RSpec Tests

#### spec/services/stripe_tap_to_pay_service_spec.rb
```ruby
require 'rails_helper'

RSpec.describe StripeTapToPayService do
  let(:business) { create(:business, stripe_account_id: 'acct_test123') }
  let(:user) { create(:user, business: business) }
  
  describe '.create_connection_token' do
    it 'creates a connection token for Terminal SDK' do
      # Test implementation
    end
  end
  
  describe '.register_tap_to_pay_reader' do
    it 'registers a new tap to pay reader' do
      # Test implementation
    end
  end
  
  describe '.create_terminal_payment_intent' do
    it 'creates a payment intent for terminal collection' do
      # Test implementation
    end
  end
  
  describe '.process_payment_result' do
    it 'processes successful payment' do
      # Test implementation
    end
    
    it 'handles failed payment' do
      # Test implementation
    end
  end
end
```

#### spec/system/tap_to_pay_flow_spec.rb
```ruby
require 'rails_helper'

RSpec.describe 'Tap to Pay Flow', type: :system, js: true do
  let(:business) { create(:business, stripe_account_id: 'acct_test') }
  let(:user) { create(:user, :manager, business: business) }
  
  before do
    login_as(user)
    # Mock iOS user agent
    page.driver.add_headers('User-Agent' => 'Mozilla/5.0 (iPhone14,2; iOS 16_4)')
  end
  
  describe 'Quick Sale with Tap to Pay' do
    it 'completes a quick sale payment' do
      visit business_manager_pos_dashboard_path
      
      click_on 'Quick Sale'
      
      within '#payment_modal' do
        fill_in 'Amount', with: '25.00'
        fill_in 'Description', with: 'Test sale'
        click_on 'Proceed to Payment'
      end
      
      expect(page).to have_content('$25.00')
      expect(page).to have_button('Tap to Pay')
      
      # Test payment flow
      # Note: Full Terminal SDK testing requires Stripe test mode
    end
  end
end
```

## Progressive Web App Configuration

### app/views/layouts/business_manager.html.erb additions
```erb
<% if ios_device? %>
  <!-- iOS PWA tags -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="BizBlasts POS">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  
  <!-- Viewport for mobile -->
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<% end %>

<!-- Include Stripe Terminal SDK -->
<script src="https://terminal.stripe.com/v1/"></script>
```

## Deployment Checklist

### Prerequisites
- [ ] Apply for Stripe Tap to Pay on iPhone access
- [ ] Get approval from Stripe
- [ ] Enable Terminal API in Stripe Dashboard
- [ ] Configure production webhook endpoints

### Database
- [ ] Run migrations on production
- [ ] Verify indexes are created

### Configuration
- [ ] Set STRIPE_SECRET_KEY environment variable
- [ ] Configure STRIPE_WEBHOOK_SECRET
- [ ] Enable HTTPS on all payment pages
- [ ] Configure CSP headers to allow Stripe Terminal SDK

### Testing
- [ ] Test with Stripe test mode
- [ ] Test on actual iPhone XS or later with iOS 16.4+
- [ ] Test payment flow end-to-end
- [ ] Test refund flow
- [ ] Test offline handling
- [ ] Verify receipts are sent correctly

### Documentation
- [ ] Create user guide for business users
- [ ] Create troubleshooting guide
- [ ] Document supported devices and iOS versions
- [ ] Create training videos

### Monitoring
- [ ] Set up error tracking for payment failures
- [ ] Monitor successful payment rate
- [ ] Track device compatibility issues
- [ ] Set up alerts for Stripe webhook failures

## Security Considerations

1. **Authentication**: All Terminal endpoints require authenticated business user
2. **HTTPS Required**: Tap to Pay only works over HTTPS
3. **Device Verification**: Verify iOS device and version before allowing access
4. **Session Management**: Payment collection sessions expire after 5 minutes
5. **Audit Trail**: Log all payment attempts and outcomes
6. **PCI Compliance**: No card data stored locally, all handled by Stripe

## Known Limitations

1. **iOS Only**: Tap to Pay only works on iPhone XS or later with iOS 16.4+
2. **Safari Required**: Must use Safari browser, not Chrome or other browsers
3. **Network Required**: Cannot process payments offline
4. **Contactless Only**: Only accepts tap payments (NFC), not chip or swipe
5. **Region Restrictions**: Available in US, UK, Australia, and select other countries

## Support & Troubleshooting

### Common Issues

1. **"Device not compatible"**
   - Ensure iPhone XS or later
   - Update to iOS 16.4 or later
   - Use Safari browser

2. **"Reader not found"**
   - Re-register the device
   - Check Stripe Terminal settings
   - Ensure location services enabled

3. **"Payment failed"**
   - Check internet connection
   - Verify Stripe account status
   - Check for sufficient funds on customer card

### Contact Support
- Stripe Terminal Support: https://support.stripe.com/terminal
- BizBlasts Support: support@bizblasts.com

## Future Enhancements

1. **Offline Mode**: Queue payments when offline, process when connection restored
2. **Receipt Customization**: Allow businesses to customize receipt format
3. **Inventory Integration**: Automatically update stock after sales
4. **Staff Permissions**: Role-based access to POS features
5. **Analytics Dashboard**: Real-time sales analytics and reporting
6. **Multi-Location Support**: Handle multiple store locations
7. **Customer Display**: Show payment amount to customer on their device
8. **Loyalty Integration**: Apply loyalty points and rewards during payment

