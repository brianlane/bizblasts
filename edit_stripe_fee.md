# TODO – Refactor Stripe Fee Handling so Connected Accounts Pay Processing Fees

_Last updated: Implementation completed - ready for manual QA_

## Background
BizBlasts currently creates **destination charges** that shift Stripe's processing fees to the **platform** account.  We want the **connected Stripe account** to pay its own fees so the platform keeps its full application fee.

Key findings from code review:
1. Booking, invoice, order, and subscription flows all build `application_fee_amount`, `on_behalf_of`, and `transfer_data` objects but **do not** send the `stripe_account:` header → results in **destination charges** (platform pays fees).
2. Tip flow is already a **direct charge** (uses `stripe_account:`) so the connected account pays fees, but no application fee is taken there.
3. Adding `on_behalf_of` alone is _not_ enough—the charge type remains destination unless we create the charge _on_ the connected account.

## Stripe-recommended structure we need

```ruby
# Direct charge on connected account **with application fee**
Stripe::Checkout::Session.create(
  session_params.merge(
    payment_intent_data: {
      # ❌  REMOVE application_fee_amount if you want the connected acct to pay Stripe fees directly
      # ✅  OR keep it if you're fine with platform fee being transferred back (connected acct still pays Stripe fee on full amount)
      # application_fee_amount: platform_fee_in_cents,
      transfer_data: {
        destination: connected_id,
        amount: amount_cents - platform_fee_in_cents # platform keeps the difference
      }
    }
  ),
  { stripe_account: connected_id } # <- turns it into a direct charge
)
```

## Action Plan
- [x] **Convert every payment flow to direct charges**
  - [x] `create_payment_checkout_session_for_booking`
  - [x] `create_payment_checkout_session`
  - [x] `create_payment_intent`
  - [x] `create_tip_checkout_session`
  - [x] `create_tip_payment_session` (updated to include platform fee)
- [x] **Keep** `application_fee_amount` as requested - platform gets clean fee, connected account pays Stripe fees on full amount
- [x] **Remove** `on_behalf_of` and `transfer_data` blocks from destination charge pattern
- [x] **Always pass** the request header: `{ stripe_account: connected_id }` when creating or refunding objects
- [x] **Update refunds** (`StripeService#create_refund`) to use the header so refunds debit the connected account
- [x] **Update customer creation** to create customers on connected accounts
- [x] **Update tip platform fee calculation** to charge same rate as other payments
- [x] **Adjust tests & mocks** that expect the old destination charge pattern
- [x] **Fix tip platform fee calculation logic** to properly handle dollar amounts
- [x] **All tests passing** - stripe service and tip service tests now pass
- [ ] **Manual QA**
  - [ ] $60 test charge → connected acct net $54.96, platform net $3.00
  - [ ] Verify application fee object in dashboard
  - [ ] Webhook events arrive with `account` key for connected account

## Clarifications from conversation
* `on_behalf_of` **alone will NOT fix the issue**—it only changes merchant of record & currency rules.
* **Remove `application_fee_amount`** if you want the connected account to shoulder Stripe fees on their portion. If you keep it, understand the flow of funds.
* **Set `transfer_data[amount]** to send connected account its share _after_ your platform fee.

## Implementation Summary

✅ **COMPLETED**: All code changes have been implemented and tested successfully.

### Key Changes Made:
1. **Converted all payment flows to direct charges** - Added `{ stripe_account: business.stripe_account_id }` parameter to all Stripe API calls
2. **Removed destination charge parameters** - Eliminated `on_behalf_of` and `transfer_data` from payment intent data
3. **Kept `application_fee_amount`** - Platform gets clean application fee, connected account pays Stripe processing fees
4. **Updated customer creation** - Customers now created on connected accounts when business context available
5. **Updated refund handling** - Refunds now processed on connected accounts
6. **Added platform fees to tips** - Tips now generate platform revenue at same rate as other payments
7. **Fixed all tests** - Updated test expectations to match new direct charge pattern

### Financial Impact:
- **Before**: Platform paid all Stripe fees, netting only ~$0.96 on $60 transaction
- **After**: Connected account pays Stripe fees, platform gets clean $3.00 application fee

### Files Modified:
- `app/services/stripe_service.rb` - Core payment processing logic
- `spec/services/stripe_service_spec.rb` - Main test suite
- `spec/services/stripe_service_tips_spec.rb` - Tip-specific tests

## References
- Stripe docs: [Destination charges](https://stripe.com/docs/connect/destination-charges)
- Stripe docs: [Direct charges](https://stripe.com/docs/connect/direct-charges)

---
**Next step**: Manual QA testing to verify connected accounts pay fees correctly. 