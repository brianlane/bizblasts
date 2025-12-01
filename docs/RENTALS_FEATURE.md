# Rentals Feature Documentation

## Overview

The Rentals feature allows businesses to create and manage rental items for their customers. Rentals are an extension of the Product model (with `product_type: :rental`) and support flexible pricing, availability tracking, security deposits, and a complete booking workflow.

## Key Concepts

### Rental Products

Rentals are products with `product_type: :rental`. They extend the standard Product model with:

- **Pricing Options**: Hourly, daily, and weekly rates
- **Security Deposit**: Refundable deposit collected before pickup
- **Duration Constraints**: Minimum and maximum rental durations
- **Buffer Time**: Time between rentals for cleaning/preparation
- **Availability Tracking**: Track available quantity per rental item
- **Category Classification**: Equipment, vehicle, space, property, etc.

### Rental Booking Workflow

1. **Customer books rental** → Status: `pending_deposit`
2. **Customer pays security deposit** → Status: `deposit_paid`
3. **Staff checks out item** → Status: `checked_out`
4. **Customer returns item** → Status: `returned`
5. **Staff processes return & refund** → Status: `completed`

Alternative flows:
- Cancel before checkout → Full deposit refund
- Late return → Late fees deducted from deposit
- Damage assessment → Damage fees deducted from deposit

## Database Schema

### Products Table (Extended)

```ruby
# Rental-specific columns added to products table:
- hourly_rate: decimal
- weekly_rate: decimal
- security_deposit: decimal
- rental_quantity_available: integer (default: 1)
- min_rental_duration_mins: integer
- max_rental_duration_mins: integer
- rental_category: string
- rental_buffer_mins: integer
- allow_hourly_rental: boolean
- allow_daily_rental: boolean
- allow_weekly_rental: boolean
- location_id: foreign_key
```

### Rental Bookings Table

```ruby
create_table :rental_bookings do |t|
  t.references :business, :product, :tenant_customer
  t.datetime :start_time, :end_time
  t.string :status, :deposit_status
  t.decimal :subtotal, :security_deposit_amount, :total_amount
  t.decimal :late_fee_amount, :damage_fee_amount
  t.string :booking_number
  # ... more fields
end
```

### Business Settings

```ruby
# Business model rental settings:
- show_rentals_section: boolean (default: false)
- rental_late_fee_enabled: boolean
- rental_late_fee_percentage: decimal
- rental_buffer_mins: integer
- rental_require_deposit_upfront: boolean
- rental_reminder_hours_before: integer
```

## Key Files

### Models
- `app/models/rental_booking.rb` - Core rental booking model
- `app/models/rental_condition_report.rb` - Checkout/return condition reports
- `app/models/product.rb` - Extended with rental methods

### Services
- `app/services/rental_availability_service.rb` - Availability checking
- `app/services/rental_booking_service.rb` - Booking creation
- `app/services/stripe_service.rb` - Deposit payment processing

### Controllers
- `app/controllers/business_manager/rentals_controller.rb` - Rental CRUD
- `app/controllers/business_manager/rental_bookings_controller.rb` - Booking management
- `app/controllers/public/rentals_controller.rb` - Public catalog
- `app/controllers/public/rental_bookings_controller.rb` - Customer booking flow

### Views
- `app/views/business_manager/rentals/` - Business management views
- `app/views/business_manager/rental_bookings/` - Booking management views
- `app/views/public/rentals/` - Customer-facing views
- `app/views/public/rental_bookings/` - Customer booking flow

### Background Jobs
- `app/jobs/rental_overdue_check_job.rb` - Hourly overdue detection
- `app/jobs/rental_reminder_job.rb` - Daily reminder notifications

### Mailers
- `app/mailers/rental_mailer.rb` - Email notifications
- `app/views/rental_mailer/` - Email templates

## Routes

### Public Routes (Tenant)
```
GET  /rentals                    - List rentals
GET  /rentals/:id                - Show rental detail
GET  /rentals/:id/availability   - Get availability calendar
GET  /rentals/:id/book           - Booking form
POST /rentals/:id/create_booking - Create booking
GET  /rental_bookings/:id        - View booking
GET  /rental_bookings/:id/pay_deposit - Stripe payment
```

### Business Manager Routes
```
/manage/rentals           - Rental product CRUD
/manage/rental_bookings   - Booking management
/manage/rental_bookings/calendar - Calendar view
/manage/rental_bookings/overdue  - Overdue rentals
/manage/rental_bookings/:id/check_out
/manage/rental_bookings/:id/process_return
/manage/rental_bookings/:id/cancel
```

## Usage

### Creating a Rental Product

1. Go to `/manage/rentals`
2. Click "New Rental"
3. Fill in:
   - Name, description
   - Category (equipment, vehicle, etc.)
   - Daily rate (required), hourly rate, weekly rate (optional)
   - Security deposit amount
   - Quantity available
   - Duration constraints
4. Save

### Enabling Rentals on Homepage

1. Go to Business Settings
2. Enable "Show Rentals Section"
3. Rentals will appear on your business homepage

### Processing a Rental

1. Customer books rental online
2. Customer pays security deposit via Stripe
3. Check out item when customer arrives (record condition)
4. Customer returns item
5. Process return (assess condition, note any damage)
6. System calculates refund (minus late fees/damage)
7. Refund processed via Stripe

## API Integration

### Stripe Integration

The feature integrates with Stripe for:
- Security deposit collection via Checkout Sessions
- Deposit refunds via Stripe Refunds API
- Platform fee collection

### Webhook Handling

Add webhook handling for rental deposits in `stripe_webhooks_controller.rb`:
- `checkout.session.completed` → Mark deposit as paid
- Process refunds → Update booking status

## Testing

Run rental tests:
```bash
bundle exec rspec spec/models/rental_booking_spec.rb
bundle exec rspec spec/models/product_rental_spec.rb
bundle exec rspec spec/requests/business_manager/rentals_spec.rb
```

## Future Enhancements

1. **SMS Notifications** - Integrate with existing Twilio for SMS reminders
2. **Photo Documentation** - Upload photos during condition reports
3. **Recurring Rentals** - Support for subscription-based rentals
4. **Multi-item Bookings** - Rent multiple different items in one booking
5. **Waitlist** - Allow customers to join waitlist for unavailable items
6. **Insurance Options** - Optional rental insurance add-on

