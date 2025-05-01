# BizBlasts - Rails Project File Structure

```
bizblasts/
│
├── app/                                # Application code (standard Rails structure)
│   ├── assets/                         # Static assets
│   │   ├── images/                     # Image assets
│   │   ├── stylesheets/                # CSS and Sass files
│   │   │   ├── application.css         # CSS entry point
│   │   │   ├── components/             # Component-specific styles
│   │   │   └── themes/                 # Theme-specific styles
│   │   └── javascript/                 # JavaScript files
│   │       ├── controllers/            # Stimulus controllers
│   │       │   ├── booking/            # Booking-related controllers
│   │       │   ├── calendar/           # Calendar display controllers
│   │       │   ├── marketing/          # Marketing feature controllers
│   │       │   └── payment/            # Payment processing controllers
│   │       ├── application.js          # JS entry point
│   │       └── channels/               # ActionCable channels
│   │
│   ├── controllers/                    # Rails controllers
│   │   ├── admin/                      # Admin-specific controllers
│   │   ├── api/                        # API controllers
│   │   │   └── v1/                     # API versioning
│   │   ├── application_controller.rb   # Base controller
│   │   ├── businesses_controller.rb    # Business management
│   │   ├── dashboard_controller.rb     # Client dashboard 
│   │   ├── bookings_controller.rb      # Booking functionality
│   │   ├── services_controller.rb      # Service management
│   │   ├── staff_controller.rb         # Staff management
│   │   ├── customers_controller.rb     # Customer management
│   │   ├── invoices_controller.rb      # Invoice functionality
│   │   ├── marketing_controller.rb     # Marketing features
│   │   ├── promotions_controller.rb    # Promotional functionality
│   │   └── public_controller.rb        # Public-facing pages
│   │
│   ├── models/                         # ActiveRecord models
│   │   ├── concerns/                   # Shared model concerns
│   │   │   ├── tenant_scoped.rb        # Multi-tenancy concern
│   │   │   └── bookable.rb             # Booking functionality concern
│   │   ├── user.rb                     # User model
│   │   ├── admin_user.rb               # Admin user model
│   │   ├── business.rb                 # Business model
│   │   ├── template.rb                 # Website template model
│   │   ├── booking.rb                  # Booking/scheduling model
│   │   ├── service.rb                  # Service offering model
│   │   ├── staff_member.rb             # Staff/employee model
│   │   ├── customer.rb                 # Customer model
│   │   ├── invoice.rb                  # Invoice model
│   │   ├── payment.rb                  # Payment model
│   │   ├── page.rb                     # Website page model
│   │   ├── promotion.rb                # Promotional offers model
│   │   ├── loyalty_program.rb          # Customer loyalty program
│   │   ├── marketing_campaign.rb       # Marketing campaign model
│   │   └── sms_message.rb              # SMS message model
│   │
│   ├── views/                          # View templates
│   │   ├── layouts/                    # Layout templates
│   │   │   ├── application.html.erb    # Main application layout
│   │   │   ├── admin.html.erb          # Admin interface layout
│   │   │   ├── client.html.erb         # Client dashboard layout
│   │   │   └── tenant.html.erb         # Tenant website layout
│   │   ├── shared/                     # Shared partials
│   │   ├── admin/                      # Admin view templates
│   │   ├── dashboard/                  # Client dashboard views
│   │   ├── businesses/                 # Business management views
│   │   ├── bookings/                   # Booking system views
│   │   ├── services/                   # Service management views
│   │   ├── staff/                      # Staff management views
│   │   ├── customers/                  # Customer management views
│   │   ├── invoices/                   # Invoice system views
│   │   ├── marketing/                  # Marketing feature views
│   │   ├── promotions/                 # Promotional system views
│   │   └── templates/                  # Website template components
│   │       ├── landscaping/            # Landscaping industry templates
│   │       ├── pool_service/           # Pool service industry templates
│   │       ├── home_service/           # Home service industry templates
│   │       └── general/                # General business templates
│   │
│   ├── helpers/                        # View helpers
│   ├── mailers/                        # Email templates
│   │   ├── application_mailer.rb       # Base mailer
│   │   ├── booking_mailer.rb           # Booking notifications
│   │   ├── invoice_mailer.rb           # Invoice notifications
│   │   ├── marketing_mailer.rb         # Marketing emails
│   │   └── reminder_mailer.rb          # Appointment reminders
│   │
│   ├── jobs/                           # Background jobs
│   │   ├── application_job.rb          # Base job class
│   │   ├── booking_reminder_job.rb     # Appointment reminder
│   │   ├── sms_notification_job.rb     # SMS sending job
│   │   ├── marketing_campaign_job.rb   # Marketing email job
│   │   ├── invoice_reminder_job.rb     # Invoice reminder
│   │   └── analytics_processing_job.rb # Analytics calculation
│   │
│   ├── services/                       # Service objects
│   │   ├── tenant_manager.rb           # Multi-tenant management
│   │   ├── stripe_service.rb           # Stripe integration
│   │   ├── booking_manager.rb          # Booking operations
│   │   ├── sms_service.rb              # Twilio SMS integration
│   │   ├── calendar_sync_service.rb    # Calendar synchronization
│   │   ├── promotion_manager.rb        # Promotional functionality
│   │   └── marketing_service.rb        # Marketing operations
│   │
│   ├── middleware/                     # Custom middleware
│   │   └── tenant_middleware.rb        # Multi-tenant middleware
│   │
│   └── admin/                          # ActiveAdmin configurations
│       ├── dashboard.rb                # Admin dashboard
│       ├── business.rb                 # Business admin
│       ├── user.rb                     # User admin
│       ├── booking.rb                  # Booking admin
│       ├── service.rb                  # Service admin
│       ├── staff_member.rb             # Staff admin
│       ├── marketing_campaign.rb       # Marketing admin
│       └── promotion.rb                # Promotion admin
│
├── config/                             # Rails configuration
│   ├── initializers/                   # Initialization code
│   │   ├── active_admin.rb             # ActiveAdmin configuration
│   │   ├── acts_as_tenant.rb           # acts_as_tenant gem configuration
│   │   ├── assets.rb                   # Asset pipeline (Propshaft) configuration
│   │   ├── cors.rb                     # Cross-Origin Resource Sharing config (if needed for API)
│   │   ├── devise.rb                   # Devise configuration
│   │   ├── filter_parameter_logging.rb # Parameter filtering for logs
│   ├── environments/                   # Environment-specific configs
│   ├── routes.rb                       # URL routing
│   ├── database.yml                    # Database configuration
│   ├── storage.yml                     # ActiveStorage configuration
│   └── tailwind.config.js              # TailwindCSS configuration (used by cssbundling)
│
├── app/overrides/                    # Solidus view customizations (Deface overrides)
│
├── db/                                 # Database configurations
│   ├── migrate/                        # Database migrations (YYYYMMDDHHMMSS_*.rb)
│   │   ├── ...                       # Existing BizBlasts migrations
│   │   ├── ...                       # Migration for products table
│   │   ├── ...                       # Migration for orders table
│   │   ├── ...                       # Migration for line_items table
│   │   ├── ...                       # Migration for product_variants table (optional)
│   │   ├── ...                       # Migration for categories table (optional)
│   │   └── ...                       # Solidus core migrations (e.g., yyyyMMddhhmmss_create_spree_tables.rb)
│   ├── schema.rb                       # Current database schema
│   └── seeds.rb                        # Seed data script
│
├── lib/                                # Library code
│   ├── assets/                         # Non-managed assets (if any)
│   ├── tasks/                          # Rake tasks
│   │   ├── tenant.rake                 # Multi-tenant management tasks
│   │   ├── booking_stats.rake          # Booking analytics tasks
│   │   ├── marketing_reports.rake      # Marketing report tasks
│   │   ├── location_sync.rake          # Multi-location sync tasks
│   │   └── document_cleanup.rake       # Document management tasks
│   ├── templates/                      # Template generators
│   │   ├── landscaping/                # Landscaping template generators
│   │   ├── pool_service/               # Pool service template generators
│   │   └── general/                    # General template generators
│   ├── sms/                            # SMS functionality
│   │   ├── message_templates.rb        # SMS template management
│   │   └── delivery_processor.rb       # SMS delivery handling
│   ├── forms/                          # Form system
│   │   ├── field_types.rb              # Form field type definitions
│   │   ├── conditional_logic.rb        # Logic implementation
│   │   └── validation_rules.rb         # Validation implementation
│   └── documents/                      # Document handling
│       ├── storage_manager.rb          # Document storage
│       ├── verification_workflow.rb    # Verification process
│       └── expiration_handler.rb       # Expiration management
│
├── public/                             # Public assets
│   ├── marketing/                      # Marketing materials
│   │   ├── templates/                  # Email marketing templates
│   │   └── promotions/                 # Promotional graphics
│   ├── booking/                        # Booking widgets for embedding
│   ├── locations/                      # Location-specific assets
│   │   ├── maps/                       # Location map images
│   │   └── icons/                      # Location markers and icons
│   ├── forms/                          # Form templates and assets
│   │   ├── styles/                     # Form styling templates
│   │   └── scripts/                    # Form behavior scripts
│   └── documents/                      # Document-related assets
│       ├── templates/                  # Document templates
│       └── icons/                      # Document type icons
│
├── vendor/                             # Third-party code (managed by Bundler, usually empty)
│
├── spec/                               # RSpec tests
│   ├── models/                         # Model tests
│   ├── controllers/                    # Controller tests
│   ├── features/                       # Feature tests
│   │   ├── booking_spec.rb             # Booking system tests
│   │   ├── marketing_spec.rb           # Marketing feature tests
│   │   └── mobile_spec.rb              # Mobile responsiveness tests
│   ├── services/                       # Service tests
│   ├── factories/                      # Test factories
│   └── support/                        # Test support files
│
├── .github/                            # GitHub configuration
│   └── workflows/                      # GitHub Actions workflows
│       ├── test.yml                    # Test automation
│       └── deploy.yml                  # Deployment automation
│
├── Gemfile                             # Ruby dependencies (Bundler)
├── Gemfile.lock                        # Locked dependency versions
├── Procfile                          # Production process definitions (for Render)
├── .env                              # Environment variables (development, gitignored)
├── .env.example                      # Example environment variables
├── README.md                           # Project documentation
└── render.yaml                         # Render deployment configuration
```

## Key Directories and Components Explained

### Enhanced Booking System

The booking system is implemented across multiple components:

```ruby
# app/models/booking.rb
class Booking < ApplicationRecord
  include TenantScoped
  
  belongs_to :service
  belongs_to :staff_member, optional: true
  belongs_to :customer
  
  has_one :invoice, dependent: :nullify
  
  validates :start_time, :end_time, presence: true
  
  scope :upcoming, -> { where('start_time > ?', Time.current) }
  scope :past, -> { where('end_time < ?', Time.current) }
  scope :for_staff, ->(staff_id) { where(staff_member_id: staff_id) }
  
  after_create :send_confirmation
  after_update :send_update_notification, if: :saved_change_to_start_time?
  before_destroy :send_cancellation_notification
  
  def duration
    (end_time - start_time) / 60 # in minutes
  end
  
  def send_sms_reminder
    SmsService.send_reminder(self)
  end
  
  private
  
  def send_confirmation
    BookingMailer.confirmation(self).deliver_later
    SmsService.send_confirmation(self) if customer.sms_notifications_enabled?
  end
  
  def send_update_notification
    BookingMailer.update_notification(self).deliver_later
    SmsService.send_update(self) if customer.sms_notifications_enabled?
  end
  
  def send_cancellation_notification
    BookingMailer.cancellation(self).deliver_later
    SmsService.send_cancellation(self) if customer.sms_notifications_enabled?
  end
end
```

### SMS Integration Service

The SMS functionality is implemented using Twilio:

```ruby
# app/services/sms_service.rb
class SmsService
  def self.send_reminder(booking)
    message = message_for_reminder(booking)
    send_message(booking.customer.phone, message)
  end
  
  def self.send_confirmation(booking)
    message = message_for_confirmation(booking)
    send_message(booking.customer.phone, message)
  end
  
  def self.send_update(booking)
    message = message_for_update(booking)
    send_message(booking.customer.phone, message)
  end
  
  def self.send_cancellation(booking)
    message = message_for_cancellation(booking)
    send_message(booking.customer.phone, message)
  end
  
  private
  
  def self.message_for_reminder(booking)
    # Load template and customize with booking details
    template = SmsTemplates.reminder_template
    template.gsub!('%CUSTOMER_NAME%', booking.customer.first_name)
    template.gsub!('%SERVICE_NAME%', booking.service.name)
    template.gsub!('%DATE%', booking.start_time.strftime('%A, %B %d'))
    template.gsub!('%TIME%', booking.start_time.strftime('%l:%M %p'))
    template.gsub!('%BUSINESS_NAME%', acts_as_tenant::Tenant.current)
    template
  end
  
  def self.send_message(to, body)
    client = Twilio::REST::Client.new(
      Rails.application.credentials.twilio[:account_sid],
      Rails.application.credentials.twilio[:auth_token]
    )
    
    client.messages.create(
      from: Rails.application.credentials.twilio[:phone_number],
      to: to,
      body: body
    )
  end
end
```

### Marketing Feature Implementation

The marketing system is implemented with multiple components:

```ruby
# app/models/promotion.rb
class Promotion < ApplicationRecord
  include TenantScoped
  
  has_many :redemptions
  
  validates :name, :discount_amount, :discount_type, :valid_from, :valid_until, presence: true
  validates :discount_type, inclusion: { in: %w[percentage fixed] }
  validates :discount_amount, numericality: { greater_than: 0 }
  validates :code, presence: true, uniqueness: { scope: :tenant_id }
  
  scope :active, -> { where('valid_from <= ? AND valid_until >= ?', Time.current, Time.current) }
  scope :expired, -> { where('valid_until < ?', Time.current) }
  scope :upcoming, -> { where('valid_from > ?', Time.current) }
  
  def active?
    valid_from <= Time.current && valid_until >= Time.current
  end
  
  def expired?
    valid_until < Time.current
  end
  
  def upcoming?
    valid_from > Time.current
  end
  
  def calculate_discount(amount)
    if discount_type == 'percentage'
      (amount * (discount_amount / 100.0)).round(2)
    else
      [discount_amount, amount].min # Don't discount more than the amount
    end
  end
  
  def usage_count
    redemptions.count
  end
  
  def within_usage_limit?
    usage_limit.nil? || usage_count < usage_limit
  end
end
```

### Multi-Tenant Architecture

The multi-tenant system uses the acts_as_tenant gem for schema separation:

```ruby
# app/middleware/tenant_middleware.rb
class TenantMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    domain = request.host.downcase
    acts_as_tenant::Tenant.switch!(tenant_for_domain(domain))
    @app.call(env)
  end

  private

  def tenant_for_domain(domain)
    # Logic to identify tenant from domain
    business = Business.find_by(custom_domain: domain) || 
               Business.find_by(subdomain: domain.split('.').first)
    business&.schema_name || 'public'
  end
end
```

### Calendar Integration

Calendar synchronization with external services:

```ruby
# app/services/calendar_sync_service.rb
class CalendarSyncService
  def self.sync_google_calendar(business)
    return unless business.google_calendar_enabled?
    
    # Get all upcoming bookings
    bookings = acts_as_tenant::Tenant.switch(business.schema_name) do
      Booking.upcoming.includes(:service, :staff_member, :customer)
    end
    
    # Initialize Google Calendar API
    service = initialize_google_service(business)
    
    # Sync each booking
    bookings.each do |booking|
      sync_booking_to_google(service, booking)
    end
  end
  
  def self.generate_ical_feed(business)
    calendar = Icalendar::Calendar.new
    
    # Set calendar properties
    calendar.prodid = "-//BizBlasts//#{business.name}//EN"
    calendar.calscale = "GREGORIAN"
    
    # Get all upcoming bookings
    bookings = acts_as_tenant::Tenant.switch(business.schema_name) do
      Booking.upcoming.includes(:service, :staff_member, :customer)
    end
    
    # Add events to calendar
    bookings.each do |booking|
      add_booking_to_ical(calendar, booking)
    end
    
    calendar.to_ical
  end
  
  private
  
  def self.initialize_google_service(business)
    # Initialize Google Calendar API client
    # Authentication using OAuth credentials stored for the business
  end
  
  def self.sync_booking_to_google(service, booking)
    # Create or update Google Calendar event
  end
  
  def self.add_booking_to_ical(calendar, booking)
    event = Icalendar::Event.new
    event.dtstart = booking.start_time
    event.dtend = booking.end_time
    event.summary = "#{booking.service.name} with #{booking.staff_member&.name || 'Staff'}"
    event.description = booking.notes if booking.notes.present?
    event.location = booking.location if booking.location.present?
    
    calendar.add_event(event)
  end
end
```

### Mobile-Optimized Views

Example of a mobile-optimized booking form:

```erb
<!-- app/views/bookings/_mobile_form.html.erb -->
<div class="w-full max-w-md mx-auto">
  <%= form_with(model: booking, class: "space-y-4") do |form| %>
    <div class="mb-4">
      <%= form.label :service_id, class: "block text-sm font-medium text-gray-700" %>
      <%= form.collection_select :service_id, 
                               services, 
                               :id, 
                               :name, 
                               {}, 
                               class: "mt-1 block w-full py-3 px-3 border border-gray-300 bg-white rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 text-base" %>
    </div>
    
    <div class="mb-4">
      <%= form.label :staff_member_id, class: "block text-sm font-medium text-gray-700" %>
      <%= form.collection_select :staff_member_id, 
                               staff_members, 
                               :id, 
                               :name, 
                               { include_blank: "Any available staff" }, 
                               class: "mt-1 block w-full py-3 px-3 border border-gray-300 bg-white rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 text-base" %>
    </div>
    
    <div class="mb-4">
      <%= form.label :date, class: "block text-sm font-medium text-gray-700" %>
      <%= form.date_field :date, 
                        value: @date, 
                        class: "mt-1 block w-full py-3 px-3 border border-gray-300 bg-white rounded-md shadow-sm focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 text-base" %>
    </div>
    
    <div class="mb-6">
      <%= form.label :time_slot, class: "block text-sm font-medium text-gray-700" %>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-2 mt-1">
        <% @available_slots.each do |slot| %>
          <label class="relative">
            <%= form.radio_button :time_slot, slot.strftime("%H:%M"), class: "sr-only peer" %>
            <div class="border rounded-md py-3 px-2 text-center peer-checked:bg-indigo-100 peer-checked:border-indigo-500 hover:bg-gray-50 cursor-pointer">
              <%= slot.strftime("%l:%M %p").strip %>
            </div>
          </label>
        <% end %>
      </div>
    </div>
    
    <div class="flex items-center justify-between">
      <%= form.submit "Book Appointment", class: "w-full py-3 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500" %>
    </div>
  <% end %>
</div>
```

The Rails application leverages the framework's convention-over-configuration approach to organize code logically while implementing all the enhanced features including advanced booking, SMS notifications, marketing functionality, and mobile optimization.

### Product Feature (Custom)

*   Adds models like `Product`, `Order`, `LineItem`.
*   Adds controllers like `ProductsController`, `OrdersController`, `CartController`.
*   Adds corresponding views and ActiveAdmin resources.
*   Migrations for new tables will be in `db/migrate/`.
