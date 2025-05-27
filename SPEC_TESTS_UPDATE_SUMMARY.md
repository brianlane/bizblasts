# Spec Tests Update Summary

## Overview
This document summarizes all the spec test updates made to align with the new tax calculation behavior for booking-based invoices. The changes ensure that all tests properly expect and verify that booking-based invoices now automatically include tax calculations using the business's default tax rate.

## Key Changes Made

### 1. Business Factory Updates (`spec/factories/businesses.rb`)
- **Added**: `:with_default_tax_rate` trait to create businesses with a default tax rate
- **Purpose**: Ensures test businesses have the required default tax rate for proper invoice tax calculations
- **Usage**: `create(:business, :with_default_tax_rate)`

### 2. Invoice Factory Updates (`spec/factories/invoices.rb`)
- **Enhanced**: `:with_booking` trait to automatically assign default tax rates
- **Added**: `:with_tax_rate` trait for explicit tax rate assignment
- **Behavior**: 
  - Creates default tax rate if business doesn't have one
  - Assigns tax rate to invoice for proper calculations
  - Lets invoice model handle amount calculations via `calculate_totals`

### 3. New Factory Created (`spec/factories/booking_product_add_ons.rb`)
- **Created**: Factory for `BookingProductAddOn` model
- **Features**: 
  - Supports quantity variations with `:with_quantity` trait
  - Automatically calculates price and total_amount
  - Integrates with booking and product_variant associations

### 4. Invoice Model Tests (`spec/models/invoice_spec.rb`)
- **Added**: New test context for "booking-based invoice calculations"
- **Tests**:
  - Verifies tax calculations for simple booking invoices
  - Verifies tax calculations for bookings with product add-ons
  - Expects 9.8% tax rate application
  - Validates proper total amount calculations

### 5. StripeService Tests (`spec/services/stripe_service_spec.rb`)
- **Updated**: `handle_booking_payment_completion` test
- **Added**: Default tax rate creation and verification
- **Expectations**: 
  - Invoice has assigned tax rate
  - Tax amount is correctly calculated (9.8% of service price)
  - Total amount includes tax

### 6. Public::BookingController Tests (`spec/controllers/public_booking_controller_spec.rb`)
- **Updated**: Business factory to use `:with_default_tax_rate` trait
- **Enhanced**: All booking creation tests to verify tax calculations
- **Verifications**:
  - Invoice has tax rate assigned
  - Tax amount is calculated correctly
  - Total amount includes tax
  - Applies to client, staff, and manager booking scenarios

### 7. System Tests Updates

#### Stripe Payment Flows (`spec/system/stripe_payment_flows_spec.rb`)
- **Updated**: Business factory to include default tax rate
- **Enhanced**: Client and guest booking tests
- **Verifications**: Tax calculations for different service prices

#### Guest Booking Flow (`spec/system/guest_booking_flow_spec.rb`)
- **Updated**: Business factory to include default tax rate
- **Enhanced**: Both guest booking scenarios
- **Verifications**: Tax rate assignment and positive tax amounts

### 8. Promotion Manager Tests (`spec/services/promotion_manager_spec.rb`)
- **Updated**: Invoice creation to include default tax rate
- **Purpose**: Ensures promotion calculations work correctly with tax-enabled invoices

### 9. Rake Task Tests (`spec/lib/tasks/fix_booking_invoice_taxes_spec.rb`)
- **Created**: Comprehensive test suite for the tax fixing rake task
- **Test Scenarios**:
  - Fixing invoices without tax rates
  - Handling businesses without default tax rates
  - Skipping invoices that already have tax rates
- **Verifications**: Proper tax amount calculations and output messages

## Tax Calculation Expectations

All updated tests now expect the following tax behavior:

### Standard Tax Rate
- **Rate**: 9.8% (0.098)
- **Name**: "Default Tax"
- **Application**: Automatically applied to all booking-based invoices

### Calculation Examples
- **$50 service**: $4.90 tax, $54.90 total
- **$80 service**: $7.84 tax, $87.84 total  
- **$100 service**: $9.80 tax, $109.80 total
- **$200 service + add-ons**: $19.60 tax, $219.60 total

### Test Verification Pattern
```ruby
# Verify invoice has proper tax calculations
invoice = booking.invoice
expect(invoice.tax_rate).to be_present
expect(invoice.tax_rate).to eq(business.default_tax_rate)
expect(invoice.original_amount).to be_within(0.01).of(expected_amount)
expect(invoice.tax_amount).to be_within(0.01).of(expected_tax)
expect(invoice.total_amount).to be_within(0.01).of(expected_total)
```

## Benefits of Updates

### 1. Comprehensive Coverage
- All booking scenarios now test tax calculations
- Both controller and system tests verify behavior
- Edge cases like product add-ons are covered

### 2. Realistic Test Data
- Businesses have default tax rates like production
- Invoices behave exactly as they would in real usage
- Tax calculations are verified at multiple levels

### 3. Regression Prevention
- Tests will catch if tax calculations break
- Ensures new booking features maintain tax compliance
- Validates rake task for fixing existing data

### 4. Documentation Value
- Tests serve as documentation for expected tax behavior
- Clear examples of how tax calculations should work
- Demonstrates proper factory usage patterns

## Running the Tests

### Individual Test Suites
```bash
# Invoice model tests
bundle exec rspec spec/models/invoice_spec.rb

# Booking controller tests  
bundle exec rspec spec/controllers/public_booking_controller_spec.rb

# StripeService tests
bundle exec rspec spec/services/stripe_service_spec.rb

# Rake task tests
bundle exec rspec spec/lib/tasks/fix_booking_invoice_taxes_spec.rb

# System tests
bundle exec rspec spec/system/guest_booking_flow_spec.rb
bundle exec rspec spec/system/stripe_payment_flows_spec.rb
```

### Full Test Suite
```bash
# Run all tests to ensure no regressions
bundle exec rspec
```

## Conclusion

These spec test updates ensure that the new tax calculation behavior for booking-based invoices is thoroughly tested and verified. The tests now accurately reflect the production behavior where:

1. All booking-based invoices automatically get tax rates assigned
2. Tax calculations are performed correctly
3. Total amounts include tax
4. The system handles various booking scenarios (simple bookings, bookings with add-ons, different user types)

The updated tests provide confidence that the tax calculation feature works correctly and will continue to work as the codebase evolves. 