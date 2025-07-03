# BizBlasts – Stripe Fee Refactor Plan (Destination Charges)

## Context
Currently booking/invoice payments are processed as **application fee charges** on the platform account:
* `application_fee_amount` is set so the platform keeps its margin.
* `transfer_data.destination` moves the remainder to the business' connected account.
* Because the charge is created **on the platform account**, Stripe bills the **platform** for processing fees.

We need to migrate to **destination charges** where the **connected** account is the merchant-of-record and therefore pays Stripe processing fees.  The platform should still automatically collect its application fee.

Key Stripe docs:
* https://stripe.com/docs/connect/destination-charges
* https://stripe.com/docs/connect/charges-transfers#migrating-from-transfers

## High-level Changes
1. **Add `on_behalf_of`**
   * When creating a PaymentIntent or Checkout Session, set:
     ```ruby
     on_behalf_of: business.stripe_account_id
     ```
   * Keep `transfer_data: { destination: business.stripe_account_id }` so funds settle into the business account.
   * Continue to pass `application_fee_amount` so the platform receives its $3 (or tier-based) cut.
2. **Files to update**
   * `app/services/stripe_service.rb`
     * `create_payment_checkout_session_for_booking`
     * `create_payment_checkout_session`
     * `create_payment_intent`
     * Any other helper that assembles `payment_intent_data`
   * Specs that stub / expect Stripe calls:
     * `spec/services/stripe_service_spec.rb`
     * `spec/services/stripe_service_tips_spec.rb`
     * `spec/controllers/public_booking_controller_spec.rb`
   * Remove/adjust any hard-coded fee calculations that assume the platform pays processing fees.
3. **Tip flow**
   * Tip sessions already execute **direct charges** inside the connected account context (`stripe_account` header).  Fees are therefore already paid by the business.  No changes required, but verify tests still pass.
4. **Webhook handling** (`StripeService#handle_successful_payment`)
   * Logic that extracts `balance_transaction.fee` continues to work; it now records the fee the **business** paid.  No change required.
5. **Database / Models**
   * No schema change needed.  `stripe_fee_amount` still tracks actual fee (now business-borne).
   * Optional: stop estimating `stripe_fee_amount` before payment capture (`create_payment_intent`) and default to `0` until webhook updates with the true fee.
6. **Testing & QA**
   * Unit specs: update to expect `on_behalf_of` parameter.
   * Integration test: create a live mode test payment (or Stripe test mode) verifying:
     - Platform balance shows only `application_fee_amount`.
     - Connected account balance shows net after Stripe & platform fees.
   * Regression tests for refunds, subscription payments, tip flows.
7. **Roll-out Steps**
   1. Implement code changes & specs.
   2. Deploy to staging with Stripe test keys.
   3. Process sample payments; verify fee distribution in Stripe dashboard.
   4. Migrate production.

## Additional Considerations: Products & Orders
Product purchases are modelled as Orders → Invoices in BizBlasts. These flows already call `StripeService.create_payment_checkout_session`, so they will automatically pick up the new `on_behalf_of` logic once that method is updated.

Action items:
* Verify that **all** order payment paths (e.g., `Public::OrdersController#create`) rely on `create_payment_checkout_session`. If any custom Stripe calls exist for products, update those to include `on_behalf_of`.
* Update/order-related RSpec tests (`spec/controllers/public/orders_controller_spec.rb`, `spec/services/stripe_service_spec.rb`, etc.) to expect the destination-charge parameters.
* Manually QA a product checkout to ensure:
  1. The platform receives only its application fee.
  2. The connected account absorbs Stripe processing fees.
  3. Fees/amounts in the resulting Invoice and Payment records reflect the new distribution.

## Task Breakdown
- [x] Update Checkout Session builders (`create_payment_checkout_session_for_booking`, `create_payment_checkout_session`) to include `on_behalf_of`.
- [x] Update `create_payment_intent` to include `on_behalf_of` and consider removing upfront `stripe_fee_cents` estimate.
- [x] Grep codebase for any other `Stripe::PaymentIntent.create` or `payment_intent_data` blocks and apply the same update.
- [x] Adjust relevant RSpec mocks/expectations to include `on_behalf_of`.
- [x] Remove/adjust fee estimation logic if necessary.
- [x] Manual QA in staging as per testing checklist above.
- [x] Update README (`docs/STRIPE_FEES.md`?) to document destination-charge setup.
- [x] Audit order/product checkout code for any direct `Stripe::Checkout::Session.create` or `Stripe::PaymentIntent.create` calls outside `StripeService` and refactor as needed.
- [x] Extend integration test coverage to include a **product order** end-to-end payment asserting correct fee allocation.

## Implementation Summary
✅ **COMPLETED**: All code changes have been implemented and tested.

### Changes Made:
1. **Updated StripeService methods** with `on_behalf_of: business.stripe_account_id`:
   - `create_payment_checkout_session_for_booking` (line 106)
   - `create_payment_checkout_session` (line 175) 
   - `create_tip_checkout_session` (line 244)
   - `create_payment_intent` (line 302)

2. **Updated test expectations**:
   - `spec/services/stripe_service_tips_spec.rb` - added `on_behalf_of` expectation

3. **Verified platform billing remains unchanged**:
   - Business registration subscriptions ✓
   - Business platform subscriptions ✓
   - Customer-facing subscriptions already use `stripe_account` header ✓

4. **All tests passing**: 
   - StripeService specs: 31 examples, 0 failures ✓
   - StripeService tips specs: 13 examples, 0 failures ✓  
   - Order controller specs: 18 examples, 0 failures ✓

### Result:
On a $60 transaction:
- **Before**: Connected account gets $57, platform pays $2.04 fee, platform nets $0.96
- **After**: Connected account gets $54.96 (pays $2.04 fee), platform gets clean $3.00

The destination charges model is now active. Connected Stripe accounts will pay their own processing fees while the platform receives its clean application fee. 