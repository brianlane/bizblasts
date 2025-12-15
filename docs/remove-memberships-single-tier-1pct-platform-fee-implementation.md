# Remove BizBlasts Memberships, Single Tier, 1% Platform Fee (Implementation Plan)

_Last updated: 2025-12-14_

## Goals (what we are doing)

- **No BizBlasts monthly membership fees** (remove Standard/Premium monthly plans and all associated billing flows).
- **No tiers**: remove Free/Standard/Premium entirely; all businesses get access to what were previously “Premium” features.
- **Platform fee is always 1%** (replacing all 3% / 5% tier-based fee logic).
- **Remove BizBlasts platform referral/loyalty program** (referral codes that reward “BizBlasts points”, “50% off first month”, etc.).
- **Keep customer subscriptions** (businesses can still sell recurring product/service subscriptions to customers).
- **Update all frontend UI/copy** to remove references to tiers, monthly fees, and old platform fee percentages.

## Non-goals (explicitly not doing)

- Removing business-level referral or loyalty programs for *customers* (these are separate from BizBlasts platform referrals). Keep unless you later request otherwise.
- Removing customer subscriptions (keep `CustomerSubscription` and tenant `/subscriptions` checkout).

## Key Definitions (to avoid confusion)

There are two separate “subscription” concepts in the codebase:

1. **BizBlasts membership subscription (to be removed)**
   - Businesses paying BizBlasts monthly (Free/Standard/Premium tiers).
   - Code: `Business.tier`, `Subscription` model/table, Business Manager “Subscription & Billing” settings page.

2. **Customer subscriptions (to keep)**
   - Customers subscribing to a business’s product/service.
   - Code: `CustomerSubscription`, `SubscriptionStripeService`, tenant `Public::SubscriptionsController`, subscription transactions/jobs/mailers.

This plan removes (1) while keeping (2).

---

## Current State (what exists today)

### Business tier/membership (remove)

- `Business.tier` enum: `free`, `standard`, `premium` (`app/models/business.rb`).
- Tier-based platform fee logic:
  - `StripeService.calculate_platform_fee_cents` uses 5% for non-premium and 3% for premium (`app/services/stripe_service.rb`).
  - `SubscriptionStripeService#get_application_fee_percent` uses 5% vs 3% (`app/services/subscription_stripe_service.rb`).
- Paid business signup goes through Stripe Checkout **mode: subscription**:
  - `Business::RegistrationsController` redirects to Stripe for standard/premium tiers (`app/controllers/business/registrations_controller.rb`).
  - Signup form offers Free/Standard/Premium plans (`app/views/business/registrations/new.html.erb`).
- Business Manager “Subscription & Billing” page:
  - Routes: `/manage/settings/subscription`, `/manage/settings/subscription/checkout`, `/manage/settings/subscription/portal`, `/manage/settings/subscription/downgrade`, `/manage/settings/stripe_events` (webhook)
  - Controller/view: `BusinessManager::Settings::SubscriptionsController` + `app/views/business_manager/settings/subscriptions/show.html.erb`
  - Policy: `Settings::SubscriptionPolicy`

### BizBlasts platform referrals/loyalty (remove)

- Business signup accepts `platform_referral_code` and processes it.
- Business Manager “Platform loyalty” section:
  - Routes: `/manage/platform` and related endpoints.
  - Controller: `BusinessManager::PlatformController`
  - Views: `app/views/business_manager/platform/*`
- Service: `PlatformLoyaltyService`
- DB tables to remove later:
  - `platform_referrals`, `platform_discount_codes`, `platform_loyalty_transactions`

### Premium-only gating (remove / make universal)

Known enforcement points:

- Custom domains strongly associated with premium tier:
  - Validations and callbacks enforce/remove custom domain on tier downgrade (`Business` model + services/jobs).
- Staff member limits tied to tier:
  - `BusinessManager::StaffMembersController#check_tier_access` blocks staff creation and redirects to subscription billing.
- SMS limits tied to tier:
  - `SmsRateLimiter::MAX_SMS_PER_BUSINESS_PER_DAY` maps `free/standard/premium`.
  - `Business#sms_daily_limit` / `Business#can_send_sms?` also references tier.
- Website template marketplace appears tier-gated:
  - `app/javascript/controllers/template_browser_controller.js` uses `businessTier` and `template.requires_premium`.
  - `app/views/business_manager/website/templates/index.html.erb` contains tier references.
- Sidebar item gating:
  - `website_builder` sidebar entry is conditional on standard/premium (`app/helpers/sidebar_items.rb`).
- UI references to “Premium only”, “Standard vs Premium”, “Domain coverage policy”, etc.

---

## Target State (what it should look like)

- Businesses sign up with **one plan** (no monthly billing), and can optionally connect Stripe.
- **All businesses can use custom domains** (subject to DNS verification/health checks), website builder, “premium” tools, etc.
- **Platform fee = 1%** for all payment flows:
  - invoice, booking, order, tips, deposits, payment intents
  - customer subscriptions: recurring checkout / Stripe subscription objects also apply 1% (see Phase 1 nuance)
- **No BizBlasts platform referral code, points, or platform discount coupons**.
- UI shows:
  - “$0 / month” (no memberships)
  - “1% platform fee” (consistent wording)
  - no Free/Standard/Premium upgrade/downgrade flows

---

## Implementation Phases (recommended order)

### Phase 0 — Add safety rails (small, low risk)

- Introduce a single source of truth constant for platform fee rate, e.g. `PLATFORM_FEE_RATE = 0.01`.
- Add a brief comment describing the platform fee as a Stripe Connect application fee.

_No production migration needed; no membership cancellation needed (you confirmed no existing paid subscriptions)._ 

### Phase 1 — Platform fee: change from tier-based to 1%

**Backend changes**

- Update `StripeService.calculate_platform_fee_cents(amount_cents, business)`
  - Remove tier branching.
  - Always compute 1%.

- Update `SubscriptionStripeService#get_application_fee_percent`
  - Return `1.0` always.

**Important nuance: customer subscriptions checkout (keep customer subscriptions, but ensure 1% fee)**

Customer subscription checkout is currently created via:
- `Public::SubscriptionsController#create` → `StripeService.create_subscription_checkout_session` (`mode: 'subscription'`)

Today, that checkout session does not appear to apply any application fee.

Implementation choice (pick one and implement consistently):

- **Option A (preferred if supported cleanly by Stripe Checkout subscription mode)**
  - Add 1% application fee to the subscription checkout session.
  - Confirm Stripe supports application fees for subscription mode Checkout in Connect for the specific flow used.

- **Option B (more explicit control)**
  - Stop using Checkout `mode: subscription` for customer subscriptions and instead:
    - create the Stripe subscription via `SubscriptionStripeService` (which already supports `application_fee_percent`)
    - handle customer payment method collection and confirmation accordingly

We should pick the lowest-risk option that keeps the existing customer subscription UX.

**Update fee displays / calculations**

- Any UI/email that displays “3%” or “5%” must be updated to “1%”.

### Phase 2 — Remove BizBlasts memberships (monthly business subscriptions)

**Routes**

- Remove the “Subscription & Billing (Module 7)” block under `namespace :business_manager -> namespace :settings` in `config/routes.rb`:
  - `get 'subscription' ...`
  - `post 'subscription/checkout' ...`
  - `post 'subscription/portal' ...`
  - `post 'subscription/downgrade' ...`
  - `post 'stripe_events' ...` (only if solely used for BizBlasts membership billing)

**Controllers/views/policies**

- Delete/retire:
  - `app/controllers/business_manager/settings/subscriptions_controller.rb`
  - `app/views/business_manager/settings/subscriptions/show.html.erb`
  - `app/policies/settings/subscription_policy.rb`

**Business signup flow**

- Update `Business::RegistrationsController`:
  - Remove the “paid tier -> Stripe subscription checkout” branch.
  - Always create the business immediately.
  - Remove parameter handling for `tier`.

- Update `app/views/business/registrations/new.html.erb`:
  - Remove plan cards.
  - Remove “Choose Your Monthly Plan”.
  - Replace with a single-plan message: “$0/month, 1% platform fee + Stripe fees”.

**Remove business-tier Stripe plan config**

- Remove/retire:
  - `StripeService.get_stripe_price_id`
  - `STRIPE_STANDARD_PRICE_ID`, `STRIPE_PREMIUM_PRICE_ID` references
  - any code that creates/updates BizBlasts membership subscriptions

### Phase 3 — Make Premium features universal (remove tier gating)

**Custom domains**

- Update `Business` and related domain services/jobs to remove premium-only checks.
  - Keep DNS/health checks and other safety requirements.

**Website builder + template marketplace**

- Remove tier gating from:
  - `app/helpers/sidebar_items.rb` (remove `website_builder` condition)
  - `app/javascript/controllers/template_browser_controller.js` (remove `businessTier` logic and `requires_premium` gating)
  - `app/views/business_manager/website/templates/index.html.erb` (remove Premium-only labels / upgrade prompts)

**Staff members**

- Update `app/controllers/business_manager/staff_members_controller.rb`:
  - Remove `before_action :check_tier_access`
  - Remove `check_tier_access` redirects to subscription billing.
  - Ensure staff creation is allowed universally.

**SMS**

- Update SMS gating to be non-tier-based:
  - `app/services/sms_rate_limiter.rb` remove `MAX_SMS_PER_BUSINESS_PER_DAY` tier map.
  - `app/models/business.rb` remove tier-based limits (e.g. `sms_daily_limit`).

Recommendation:
- Keep hourly limits.
- Set one daily limit via a constant or env var (or remove daily limits entirely if desired).

### Phase 4 — Remove BizBlasts platform referrals/loyalty

**Signup**

- Remove `platform_referral_code` from:
  - `app/views/business/registrations/new.html.erb`
  - `app/controllers/business/registrations_controller.rb` strong params and logic

**Business Manager platform section**

- Remove `/manage/platform`:
  - Remove the `resources :platform` block in `config/routes.rb`
  - Delete/retire `app/controllers/business_manager/platform_controller.rb`
  - Delete/retire `app/views/business_manager/platform/*.html.erb`
  - Remove `platform` from:
    - `app/helpers/sidebar_items.rb`
    - registration sidebar selection defaults (currently includes `platform`)

**Service/model cleanup**

- Delete/retire `app/services/platform_loyalty_service.rb` and related platform models.

### Phase 5 — UI/copy sweep (frontend completeness)

This is the “don’t miss anything” checklist. Update or remove tier/monthly-fee/platform-referral content in these areas.

#### Public marketing pages

- `app/views/home/pricing.html.erb`
  - Remove Free/Standard/Premium sections.
  - Replace with: $0/month, 1% platform fee.
  - Remove “Most popular”, “$9.99”, “$29.99”, “3%/5%”, “Domain coverage policy”.

- `app/views/home/about.html.erb`
- `app/views/shared/_comprehensive_faq.html.erb`

#### Business signup

- `app/views/business/registrations/new.html.erb`
  - Remove tier selector UI and tier descriptions.
  - Remove premium-only domain blocks and “upgrade” language.
  - Remove platform referral code field.

#### Business Manager settings

- `app/views/business_manager/settings/index.html.erb`
  - Remove “Subscription & Billing” entry.

- `app/views/business_manager/settings/business/edit.html.erb`
  - Remove upgrade prompts.
  - Ensure custom domain controls are available.

- `app/views/shared/_domain_coverage_info.html.erb`
  - Remove or rewrite (domain coverage policy was tied to membership pricing).

#### Transaction fee references

Update any mention of fee percentage:

- `app/views/business_manager/payments/show.html.erb`
- invoice mailers: `app/views/invoice_mailer/*`
- order mailers: `app/views/order_mailer/*`
- booking mailers: `app/views/booking_mailer/*`

Use consistent phrasing:
- “BizBlasts platform fee (1%)”
- “Stripe processing fees (charged by Stripe)”

#### Remove BizBlasts platform referral UI

- All `app/views/business_manager/platform/*` (removed)
- `app/controllers/public/referral_controller.rb` and its views/routes if those pages are BizBlasts platform referral pages (confirm intent; default action is to remove BizBlasts platform referrals, not business customer referrals).

### Phase 6 — Database cleanup (after behavior is stable)

Since there are **no existing paid subscriptions**, cleanup can be direct once code is stable.

**Drop BizBlasts membership artifacts**

- Remove `subscriptions` table and `Subscription` model.

**Drop platform referral artifacts**

- Remove tables:
  - `platform_referrals`
  - `platform_discount_codes`
  - `platform_loyalty_transactions`

**Remove unused Business columns**

- Remove columns used only by platform referrals/points (e.g. `platform_referral_code`, `platform_loyalty_points`, etc.).
  - Confirm exact columns in schema before migrating.

**Tier strategy (updated requirement: remove tiers entirely)**

- **Remove `Business.tier` from the codebase entirely**:
  - Delete the `tier` enum from `Business`.
  - Remove `tier`-based predicate methods and any `*_tier?` checks.
  - Remove the `tier` column from `businesses` via migration.
- This plan assumes **no backwards compatibility**: update/replace all call sites, specs, factories, admin filters, and API copy to not reference tiers at all.

### Phase 7 — Tests (update to reflect new product rules)

High-impact spec areas to update/remove (non-exhaustive):

- Business registration (no Stripe subscription checkout; no tier selection)
  - `spec/system/business_registration_spec.rb`
  - `spec/requests/business/registrations_spec.rb`
  - `spec/controllers/business/registrations_controller_spec.rb`

- Business Manager subscription billing settings (deleted)
  - `spec/requests/business_manager/settings/subscriptions_spec.rb`
  - `spec/requests/business_manager/settings/subscriptions_request_spec.rb`

- Staff limits (remove tier gating)
  - specs around staff creation limits and redirects.

- SMS tier limits (remove tier map)
  - `spec/services/sms_rate_limiter_spec.rb`

- Platform loyalty/referral (deleted)
  - `spec/services/platform_loyalty_service_spec.rb`
  - `spec/controllers/business_manager/platform_controller_spec.rb`
  - `spec/factories/platform_loyalty_transactions.rb`
  - `spec/services/comprehensive_referral_loyalty_spec.rb` (ensure it distinguishes business referral vs platform referral)

- Domain coverage / premium-only policies (removed)
  - `spec/system/admin/domain_coverage_management_spec.rb`
  - `spec/views/shared/_domain_coverage_info_spec.rb`
  - any custom domain specs asserting premium restriction.

- Stripe platform fee expectations (1% everywhere)
  - `spec/services/stripe_service_spec.rb`
  - `spec/services/subscription_stripe_service_spec.rb`
  - `spec/services/stripe_service_tips_spec.rb`

---

## File-by-file Change Checklist (implementation punch list)

This is the actionable checklist used during implementation.

### Billing/membership removal

- [x] `config/routes.rb`: remove BizBlasts membership routes under `/manage/settings/subscription*`.
- [x] `app/controllers/business_manager/settings/subscriptions_controller.rb`: delete.
- [x] `app/views/business_manager/settings/subscriptions/show.html.erb`: delete.
- [x] `app/policies/settings/subscription_policy.rb`: delete.
- [x] `app/models/subscription.rb`: removed.

### Signup + pricing UI

- [x] `app/views/business/registrations/new.html.erb`: remove tier UI + platform referral field; replace with single-plan copy.
- [x] `app/controllers/business/registrations_controller.rb`: remove tier + platform referral params/logic; remove Stripe membership checkout.
- [x] `app/views/home/pricing.html.erb`: replace tier pricing with $0/month + 1% fee messaging.

### Platform fee

- [x] `app/services/stripe_service.rb`: make platform fee = 1%.
- [x] `app/services/subscription_stripe_service.rb`: make application fee percent = 1%.
- [x] Customer subscription checkout: update `StripeService.create_subscription_checkout_session` to apply 1%.

### Premium features become universal

- [x] `app/models/business.rb`: remove premium-only restrictions for custom domains; remove tier downgrade domain removal.
- [x] `app/controllers/business_manager/staff_members_controller.rb`: remove tier staff cap + subscription redirect.
- [x] `app/services/sms_rate_limiter.rb`: remove tier-based limits.
- [x] `app/helpers/sidebar_items.rb`: remove tier conditions; remove platform sidebar item.
- [x] `app/javascript/controllers/template_browser_controller.js`: remove “requires premium” and “upgrade required” gating.
- [x] `app/views/business_manager/website/templates/index.html.erb`: remove any tier gating labels/prompts.

### Remove BizBlasts platform referrals/loyalty

- [x] `config/routes.rb`: remove `/manage/platform` routes.
- [x] `app/controllers/business_manager/platform_controller.rb`: delete.
- [x] `app/views/business_manager/platform/*`: delete.
- [x] `app/services/platform_loyalty_service.rb` + platform models: removed.

### Copy updates

- [x] Replace all “3%” / “5%” platform fee references with “1%” across:
  - [x] `app/views/*` (payments pages, docs partials)
  - [x] mailers (`app/views/*_mailer/*`)

### DB cleanup (after stable)

- [x] Drop tables: `subscriptions`, `platform_referrals`, `platform_discount_codes`, `platform_loyalty_transactions`.
- [x] Remove platform-referral-related Business columns.
- [x] Remove `tier` column (and all tier-related code) entirely.

---

## Acceptance Criteria (definition of done)

- No UI shows Free/Standard/Premium plan selection, upgrade/downgrade, or monthly fees.
- Public pricing page reflects: **$0/month + 1% platform fee**.
- Businesses can connect and use custom domains (no tier gating; tiers do not exist).
- Platform fee computed as **1%** for:
  - invoice payments, booking payments, order payments, tips, deposits
  - customer subscription recurring charges
- No BizBlasts platform referral code can be entered at signup.
- No “BizBlasts platform loyalty” pages/routes exist.
- No `tier` column or `Business.tier` enum exists anywhere; no tier-based code paths remain.
- All relevant specs updated and passing.

---

## Notes / Risks

- **Naming conflicts**: there are multiple “subscription” route areas:
  - `/manage/settings/subscription` (BizBlasts membership)
  - `/manage/subscriptions` (customer subscriptions management)
  - tenant `/subscriptions` (customer subscription checkout)
  - Removing the BizBlasts membership routes reduces confusion.

- **Customer subscription platform fee**: ensure the chosen approach applies 1% without breaking subscription checkout UX.

- **Tier removal is invasive**: removing the `tier` column and all `*_tier?` references will touch many files (admin, jobs, services, controllers, views, factories/specs). The implementation should include a repo-wide sweep for `tier`, `free_tier?`, `standard_tier?`, `premium_tier?`, and any UI copy referencing “Free/Standard/Premium”.

---

## Revisions & Additional Items (Code Review Findings)

_Added: 2025-12-14 after comprehensive codebase analysis_

### Additional Files Not Listed in Original Plan

The following files were identified during code review and should be added to the implementation checklist:

#### Admin Panel Files

- [x] `app/admin/subscription_reports.rb`
  - **Lines 40-56**: Contains "Business Tier" filter with free/standard/premium dropdown
  - **Action**: Remove or update the tier filter; this admin page tracks customer subscriptions but has a tier filter that needs removal

- [x] `app/admin/subscription_analytics.rb`
  - **Note**: This is about CustomerSubscription (customer subscriptions), **keep this file**
  - **No action needed**

- [x] `app/admin/businesses.rb`
  - Contains references to `premium_tier?` and domain management actions tied to tier
  - **Action**: Update domain-related admin actions to remove premium-only restrictions

- [x] `app/admin/client_websites.rb`
  - May contain tier references
  - **Action**: Audit and update if needed

- [x] `app/admin/debug.rb`
  - May contain tier debugging logic
  - **Action**: Audit and update if needed

#### Jobs

- [x] `app/jobs/domain_monitoring_job.rb`
  - Contains tier/premium references for domain monitoring logic
  - **Action**: Update to remove premium-only domain monitoring restrictions

- [x] `app/jobs/custom_domain_setup_job.rb`
  - Contains tier/premium references
  - **Action**: Update to allow custom domain setup for all businesses

- [x] `app/jobs/payment_reminder_job.rb`
  - May contain tier-based logic for payment reminders
  - **Action**: Audit and update if needed

- [x] `app/jobs/auto_cancel_unpaid_product_orders_job.rb`
  - May contain tier references
  - **Action**: Audit and update if needed

**Note**: `app/jobs/subscription_loyalty_processor_job.rb` is for **customer subscription loyalty** (business loyalty programs for customers), NOT BizBlasts platform loyalty. **Keep this file unchanged**.

#### Factories (for test updates)

- [x] `spec/factories/businesses.rb`
  - Contains tier traits (`:free_tier`, `:standard_tier`, `:premium_tier`, etc.)
  - **Action**: Remove tier traits and any `tier` attribute usage entirely (no backwards compatibility).

- [x] `spec/factories/subscriptions.rb`
  - Factory for BizBlasts membership Subscription model
  - **Action**: Delete when Subscription model is removed

- [x] `spec/factories/website_templates.rb`
  - May contain `requires_premium` attribute
  - **Action**: Update to remove premium requirement

- [x] `spec/factories/platform_referrals.rb` - Deleted
- [x] `spec/factories/platform_loyalty_transactions.rb` - Deleted
- [x] `spec/factories/platform_discount_codes.rb` - Deleted

- [x] `spec/factories/tips.rb`
  - Contains `platform_fee_cents` attribute
  - **Action**: Update expected values to reflect 1% fee

- [x] `spec/factories/payments.rb`
  - Contains `platform_fee` attribute
  - **Action**: Update expected values to reflect 1% fee

#### Helpers

- [x] `app/helpers/application_helper.rb`
  - **Line 540**: Contains `current_business&.standard_tier? || current_business&.premium_tier?` check
  - **Action**: Update to remove tier gating or make universal

#### Additional Spec Files

- [x] `spec/models/platform_referral_spec.rb` - Deleted
- [x] `spec/services/comprehensive_referral_loyalty_spec.rb`
  - **Action**: Audit to ensure it distinguishes business customer referrals (keep) from BizBlasts platform referrals (remove tests for)

- [x] `spec/models/tip_spec.rb`
  - May contain platform fee percentage expectations
  - **Action**: Update to expect 1% fee

#### Mailer Updates (expanded list)

- [x] `app/views/booking_mailer/*.html.erb` - Checked/updated for fee percentage references
- [x] `app/views/order_mailer/*.html.erb` - Checked/updated for fee percentage references
- [x] `app/views/subscription_mailer/*.html.erb` - Checked/updated for fee percentage references (customer subscriptions)

#### API Endpoints

- [x] `app/controllers/api/v1/businesses_controller.rb`
  - Contains an `ai_summary` payload that currently hardcodes **old** tiered pricing (Free/Standard/Premium), monthly fees, and **3%/5%** platform fees.
  - **Action**: Rewrite API copy to reflect **$0/month + 1% platform fee**, and remove tier-specific claims (e.g., “Premium”, “Multi-location support (Premium)”, etc.).
  - **Action**: Audit other API responses for any `tier` exposure and remove/neutralize where appropriate.

#### Webhooks

- [x] `app/controllers/webhooks/twilio_controller.rb`
  - Contains tier-based SMS fallback logic, e.g. `where.not(tier: 'free')` for auto-reply business selection and fallback business context selection.
  - **Action**: Update to remove tier-based SMS restrictions/fallbacks so behavior does not depend on `Business.tier`.

---

### Platform Fee Constant (Phase 0 Detail)

Add a centralized constant for the platform fee rate and make **all** fee calculations reference it (both `StripeService` and `SubscriptionStripeService`).

Avoid a top-level constant in a reloading environment; prefer a namespaced constant in an initializer. Suggested implementation:

```ruby
# config/initializers/bizblasts.rb
module BizBlasts
  PLATFORM_FEE_RATE = 0.01
  PLATFORM_FEE_PERCENTAGE = 1  # For display purposes
end
```

Then reference it from fee logic:

```ruby
# app/services/stripe_service.rb
def self.calculate_platform_fee_cents(amount_cents, business = nil)
  (amount_cents * BizBlasts::PLATFORM_FEE_RATE).round
end
```

---

### Environment Variables to Remove

After code changes are complete, remove these environment variables from production/staging:

- [x] `STRIPE_STANDARD_PRICE_ID` - No longer referenced in code; remove from Render/production env (manual)
- [x] `STRIPE_PREMIUM_PRICE_ID` - No longer referenced in code; remove from Render/production env (manual)

Files referencing these:
- _(none; all code references removed)_

---

### Database Migration Strategy (Phase 6 Detail)

#### Recommended migration order:

1. **First migration**: Drop platform referral tables (no dependencies)
   ```ruby
   class RemovePlatformReferralTables < ActiveRecord::Migration[8.0]
     def change
       drop_table :platform_loyalty_transactions, if_exists: true
       drop_table :platform_discount_codes, if_exists: true
       drop_table :platform_referrals, if_exists: true
     end
   end
   ```

2. **Second migration**: Remove Business columns for platform referrals
   ```ruby
   class RemovePlatformReferralColumnsFromBusinesses < ActiveRecord::Migration[8.0]
     def change
       remove_column :businesses, :platform_referral_code, :string, if_exists: true
       remove_column :businesses, :platform_loyalty_points, :integer, if_exists: true
       # Add any other platform-related columns
     end
   end
   ```

3. **Third migration**: Drop BizBlasts membership subscriptions table
   ```ruby
   class RemoveBizBlastsSubscriptionsTable < ActiveRecord::Migration[8.0]
     def change
       drop_table :subscriptions, if_exists: true
     end
   end
   ```

4. **Fourth migration (required)**: Remove tier column from businesses
  ```ruby
  class RemoveTierFromBusinesses < ActiveRecord::Migration[8.0]
    def change
      remove_column :businesses, :tier, :string, if_exists: true
    end
  end
  ```
  - Also remove any DB indexes/constraints involving `businesses.tier` (if present) and update any admin reports that query by tier.

---

### Testing Strategy (Phase 7 Expansion)

#### Test files to DELETE entirely:

- `spec/services/platform_loyalty_service_spec.rb`
- `spec/controllers/business_manager/platform_controller_spec.rb`
- `spec/factories/platform_loyalty_transactions.rb`
- `spec/factories/platform_referrals.rb`
- `spec/factories/platform_discount_codes.rb`
- `spec/models/platform_referral_spec.rb`
- `spec/requests/business_manager/settings/subscriptions_spec.rb`
- `spec/requests/business_manager/settings/subscriptions_request_spec.rb` (if exists)

#### Test files to UPDATE (not delete):

| File | Changes Required |
|------|------------------|
| `spec/services/stripe_service_spec.rb` | Update all platform fee expectations from 3%/5% to 1% |
| `spec/services/subscription_stripe_service_spec.rb` | Update application fee expectations to 1% |
| `spec/services/stripe_service_tips_spec.rb` | Update platform fee calculations |
| `spec/services/sms_rate_limiter_spec.rb` | Remove tier-based limit tests; use single limit |
| `spec/system/business_registration_spec.rb` | Remove tier selection tests; remove Stripe subscription checkout tests |
| `spec/requests/business/registrations_spec.rb` | Remove tier params and platform referral code tests |
| `spec/controllers/business/registrations_controller_spec.rb` | Remove tier and platform referral logic tests |
| `spec/services/comprehensive_referral_loyalty_spec.rb` | Keep business customer referral tests; remove BizBlasts platform referral tests |
| `spec/factories/businesses.rb` | Remove tier traits and any use of `tier`; update factories/specs to not rely on tiers |
| `spec/factories/tips.rb` | Update platform_fee_cents expectations |
| `spec/factories/payments.rb` | Update platform_fee expectations |
| `spec/models/business_spec.rb` | Remove premium-only custom domain restriction tests |
| `spec/system/admin/domain_coverage_management_spec.rb` | Remove/update domain coverage policy tests |

#### Test coverage notes

These behaviors are covered by existing tests (no new specs required for this refactor):

- Platform fee is always 1%: `spec/services/stripe_service_spec.rb`, `spec/services/stripe_service_tips_spec.rb`
- Customer subscriptions application fee percent is 1%: `spec/services/subscription_stripe_service_spec.rb`
- Signup creates business immediately (no membership checkout): `spec/requests/business/registrations_spec.rb`, `spec/system/business_registration_spec.rb`
- Custom domains available without tier gating: `spec/models/business_cname_spec.rb`, `spec/system/business_manager/custom_domain_setup_spec.rb`
- Staff access not tier-gated: `spec/requests/business_manager/staff_members_spec.rb`
- SMS limits are uniform and not tier-based: `spec/services/sms_rate_limiter_spec.rb`

---

### UI/UX Considerations

#### Copy changes across the application:

| Old Text | New Text |
|----------|----------|
| "Free plan" / "Standard plan" / "Premium plan" | "BizBlasts" (or no plan name) |
| "3% platform fee" / "5% platform fee" | "1% platform fee" |
| "Upgrade to Premium" | Remove entirely |
| "Premium only" / "Premium feature" | Remove entirely |
| "Choose Your Plan" | Remove entirely |
| "$9.99/month" / "$29.99/month" | "$0/month" |
| "Subscription & Billing" | Remove from settings menu |

#### Pricing page rewrite (`app/views/home/pricing.html.erb`):

Replace the entire tier comparison table with:

```html
<div class="pricing-simple">
  <h2>Simple, Transparent Pricing</h2>
  <div class="pricing-card">
    <h3>$0/month</h3>
    <p class="fee">1% platform fee on transactions</p>
    <p class="plus">+ Stripe processing fees</p>
    <ul>
      <li>✓ Custom domains</li>
      <li>✓ Website builder</li>
      <li>✓ Unlimited staff</li>
      <li>✓ SMS notifications</li>
      <li>✓ All features included</li>
    </ul>
    <a href="/business/sign_up" class="btn">Get Started Free</a>
  </div>
</div>
```

---

### Rollback Plan

If issues arise after deployment:

1. **Feature flag approach (recommended before deployment)**:
   - Add `PLATFORM_FEE_RATE` as an environment variable instead of hardcoded constant
   - This allows quick rollback to old rates if needed

2. **Database safety**:
  - Prefer **delaying destructive Phase 6 migrations** (dropping tables/columns) until Phase 1–5 are stable.
  - Once the tier column/table drops are deployed, rollback requires DB restore (plan backups accordingly).

3. **Monitoring**:
   - Watch Stripe dashboard for payment failures after platform fee changes
   - Monitor error logs for tier-related NoMethodError exceptions

---

### Implementation Order Recommendation

For safest rollout, implement in this order:

1. **Phase 0** - Add `PLATFORM_FEE_RATE` constant (no behavior change yet)
2. **Phase 1** - Change fee calculation to 1% (immediate revenue impact, monitor closely)
3. **Phase 3** - Remove tier gating for features (enables features for free tier users)
4. **Phase 2** - Remove membership billing routes/controllers (cleanup)
5. **Phase 4** - Remove platform referrals/loyalty (cleanup)
6. **Phase 5** - UI/copy sweep (user-facing changes)
7. **Phase 7** - Update tests (can be done incrementally with each phase)
8. **Phase 6** - Database cleanup (final, after everything is stable)

---

### Smoke Test Checklist (Post-Deployment)

After deploying each phase, verify:

- Business signup works without Stripe subscription checkout
- Existing businesses can still access their dashboards
- Custom domain setup works for all businesses
- Staff member creation works for all businesses
- SMS sending works (check rate limits are uniform)
- Website builder is accessible to all businesses
- Payments process with 1% platform fee
- Customer subscription checkout works with 1% fee
- No "Premium" or tier references visible in UI (membership/tier wording)
- Pricing page shows $0/month + 1% fee
- Settings menu no longer shows "Subscription & Billing"
- Platform referral code field is gone from signup

---

### Files Summary (Complete Count)

| Category | Files to Delete | Files to Update | Files to Keep |
|----------|----------------|-----------------|---------------|
| Controllers | 2 | 5+ | - |
| Models | 4 | 1 (Business) | CustomerSubscription, etc. |
| Views | 5+ files/dirs | 15+ | - |
| Services | 1 | 2 | SubscriptionLoyaltyService |
| Jobs | 0 | 4 | SubscriptionLoyaltyProcessorJob |
| Helpers | 0 | 2 | - |
| Admin | 0 | 3 | - |
| Specs | 8+ | 15+ | - |
| Factories | 3 | 4 | - |
| Routes | 2 blocks | 0 | - |
| Migrations | 0 (add new) | 0 | - |

**Total estimated files requiring changes: ~50+**

---

## Implementation Review & Corrections (Post-Implementation Audit)

### Summary
After reviewing the git diff against main branch, two spec files were incorrectly deleted that contained valid non-tier-related tests. These files have been recovered and updated to remove only tier-specific code.

### Files Incorrectly Deleted (Recovered)

#### 1. `spec/models/business_spec.rb`
**Issue:** Entire file was deleted, but it contained valid tests for:
- Model associations (users, services, bookings, orders, etc.)
- Hostname validation and normalization
- Time zone handling
- Logo attachment validation

**Recovery Action:** Restored from main branch, then surgically removed:
- Tier enum test
- Tier presence validation test
- `tier: 'free'` from factory subject
- "when tier is free" validation context
- Entire "domain coverage methods" describe block (premium-only feature)
- Tier references from `custom_domain_allow?` tests

#### 2. `spec/requests/admin/businesses_spec.rb`
**Issue:** Entire file was deleted, but it contained valid tests for:
- ActiveAdmin configuration
- Admin authentication
- Business CRUD operations (index, create, delete)
- Admin show page content
- Stripe connect reminder functionality

**Recovery Action:** Restored from main branch, then removed:
- `tier: :free` from business factory let block
- `tier: 'standard'` from valid_attributes
- Tier column header check in index tests
- `business.tier` checks in display tests
- `name="business[tier]"` form field check
- Entire "Domain Coverage functionality" describe block (lines 206-371)
  - This included premium-only domain coverage tests
  - Extracted and preserved the Stripe connect reminder tests that were incorrectly nested inside

### Validation
Both recovered spec files should now:
- ✅ Pass RSpec tests for non-tier functionality
- ✅ Not reference `tier` enum or tier-based logic
- ✅ Not reference domain coverage (premium-only feature being removed)
- ✅ Preserve all association, validation, and admin CRUD tests

### Commands to Verify
```bash
# Verify the recovered specs pass
COVERAGE=false bundle exec rspec spec/models/business_spec.rb --format progress
COVERAGE=false bundle exec rspec spec/requests/admin/businesses_spec.rb --format progress
```

### Lessons Learned
When removing feature-specific code:
1. **Don't delete entire spec files** - audit for non-feature tests first
2. **Domain coverage was premium-only** - all domain_coverage_* columns/tests should be removed
3. **Nested describe blocks can contain unrelated tests** - check for misplaced tests before deleting parent blocks

### 2025-12-14 Verification Notes
- Reviewed current diff vs main: removals match the plan to eliminate BizBlasts memberships, platform referrals/loyalty, tiers, and domain-coverage artifacts while keeping customer subscription flows intact.
- Updated `spec/requests/csrf_protection_spec.rb` to reflect the removal of `BusinessManager::Settings::SubscriptionsController` and removed it from the CSRF skip audit list.
- No additional file recoveries were required; new migrations remain staged for dropping membership/platform tables and tier/domain-coverage columns.
- Tests not re-run in this pass.
