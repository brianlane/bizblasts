# Rental Booking Audit Trail Setup

This document explains how to set up and use the PaperTrail audit trail for RentalBooking records.

## Overview

The audit trail tracks all changes to rental bookings for:
- Compliance and regulatory requirements
- Debugging booking issues
- Dispute resolution
- Business intelligence

## Setup Instructions

### 1. Add PaperTrail Gem

Add to `Gemfile`:

```ruby
gem 'paper_trail'
```

### 2. Install the Gem

```bash
bundle install
```

### 3. Generate PaperTrail Migration

```bash
bundle exec rails generate paper_trail:install
```

This creates a migration for the `versions` table that stores all changes.

### 4. Run the Migration

```bash
bundle exec rails db:migrate
```

### 5. Enable Versioning in RentalBooking Model

In `app/models/rental_booking.rb`, uncomment the `has_paper_trail` configuration (lines 21-34).

The configuration includes:
- **Events tracked**: create, update, destroy
- **Ignored fields**: updated_at, lock_version (these change frequently and aren't meaningful)
- **Metadata captured**:
  - `whodunnit`: Who made the change (staff member, customer, or system)
  - `business_id`: Which business the booking belongs to
  - `booking_number`: The booking identifier for easy reference

## Usage

### View Booking History

```ruby
booking = RentalBooking.find(123)

# Get all versions
booking.versions

# Get previous version
booking.paper_trail.previous_version

# Get version at specific time
booking.paper_trail.version_at(2.days.ago)

# Who made the change
booking.versions.last.whodunnit
# => "Staff: manager@example.com"
```

### Revert Changes

```ruby
# Revert to previous version
booking.paper_trail.previous_version.save!

# Revert to version at specific time
booking.paper_trail.version_at(1.week.ago).save!
```

### Query Versions

```ruby
# Find all versions for a specific booking
PaperTrail::Version.where(item_type: 'RentalBooking', item_id: booking_id)

# Find all changes by a specific person
PaperTrail::Version.where(whodunnit: 'Staff: manager@example.com')

# Find all changes to a specific business
PaperTrail::Version.where("object_changes LIKE ?", "%business_id: #{business_id}%")
```

### Admin Interface

You can add an audit trail view to the admin panel:

```ruby
# app/admin/rental_bookings.rb
ActiveAdmin.register RentalBooking do
  sidebar "Version History", only: :show do
    table_for resource.versions do
      column :event
      column :whodunnit
      column :created_at
      column "Changes" do |v|
        v.changeset.map { |k, v| "#{k}: #{v[0]} → #{v[1]}" }.join(", ")
      end
    end
  end
end
```

## Important Fields Tracked

The audit trail captures changes to all important fields:

- **Status changes**: pending_deposit → deposit_paid → checked_out → returned → completed
- **Deposit tracking**: deposit_status, deposit_amount, deposit_refund_amount
- **Pricing**: total_amount, rate_amount, security_deposit_amount
- **Timing**: start_time, end_time, actual_pickup_time, actual_return_time
- **Authorization**: deposit_authorization_id, deposit_captured_at, deposit_authorization_released_at
- **Assignments**: staff_member_id, location_id
- **Customer info**: tenant_customer_id, customer_notes, notes

## Data Retention

Consider implementing a retention policy for old versions:

```ruby
# lib/tasks/cleanup.rake
namespace :audit_trail do
  desc "Clean up old audit trail versions"
  task cleanup: :environment do
    # Keep versions for 2 years for compliance
    PaperTrail::Version
      .where(item_type: 'RentalBooking')
      .where('created_at < ?', 2.years.ago)
      .delete_all
  end
end
```

Schedule this with whenever, sidekiq-cron, or your task scheduler.

## Security Considerations

1. **Access Control**: Only admins and managers should view full audit trails
2. **PII Protection**: Audit trails may contain customer information - handle according to privacy policies
3. **Retention**: Follow regulatory requirements for how long to keep audit data
4. **Backups**: Include `versions` table in regular database backups

## Testing

Example RSpec tests for audit trail:

```ruby
RSpec.describe RentalBooking, type: :model do
  describe "audit trail" do
    let(:booking) { create(:rental_booking) }

    it "creates version on update" do
      expect {
        booking.update!(status: 'checked_out')
      }.to change { booking.versions.count }.by(1)
    end

    it "tracks who made the change" do
      booking.update!(status: 'checked_out')
      expect(booking.versions.last.whodunnit).to match(/Staff:|Customer:|System/)
    end

    it "records what changed" do
      booking.update!(status: 'checked_out')
      expect(booking.versions.last.changeset).to include('status')
    end
  end
end
```

## Troubleshooting

### Versions not being created

1. Verify PaperTrail is installed: `bundle list | grep paper_trail`
2. Check migrations ran: `rails db:migrate:status | grep versions`
3. Verify `has_paper_trail` is uncommented in the model
4. Check PaperTrail is enabled in test environment

### Performance concerns

If the versions table gets very large:

1. Add indexes on frequently queried columns:
   ```ruby
   add_index :versions, :item_type
   add_index :versions, :item_id
   add_index :versions, :created_at
   add_index :versions, :whodunnit
   ```

2. Consider partitioning by created_at date
3. Archive old versions to separate storage

## Further Reading

- [PaperTrail Documentation](https://github.com/paper-trail-gem/paper_trail)
- [Rails Guides - Active Record Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html)
