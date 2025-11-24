# TODO: Hardening Cache-Control Headers Across Public Endpoints

While we fixed invoice caching, many other guest-facing pages still risk being served from browser or proxy cache.  This checklist captures follow-up work to roll out `no-store` / `private` headers consistently and safely.

## 1. Identify All Pages That Should Never Be Cached

| Controller | Actions | Rationale |
|------------|---------|-----------|
| `Public::OrdersController` | `show`, `success`, `cancel` | Order status flips quickly via webhooks; cached pages mislead customers. |
| `Public::PaymentsController` | `new`, `success`, `cancel` | Same as above; tokenised URLs. |
| `Public::BookingController` | `confirmation`, `show` | Booking can be cancelled/paid moments later. |
| `Public::ClientBookingsController` | all | Shows live list of bookings. |
| `Public::TenantCalendarController` | all | Calendar feed must always be fresh. |
| `Public::{Tips,Subscriptions,Loyalty,Referral}Controller` | any page showing balances or states | Wallet / subscription data changes via webhooks. |
| *Any* controller that accepts `token=` / `access_token=`  params | all | URL is effectively a bearer-token – must not be cached. |

## 2. DRY Implementation Plan

1. **Create `Public::BaseController`** (inherits from `ApplicationController`).
2. Define helper:
   ```ruby
   class Public::BaseController < ApplicationController
     private
     def no_store!
       response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
       response.headers["Pragma"]        = "no-cache"
       response.headers["Expires"]       = "0"
     end
   end
   ```
3. In each public controller, `after_action :no_store!, only: [...]` per table above.
4. For **signed-in** pages that still need freshness, use
   `"private, no-store, max-age=0"` instead, to stop proxy caching but allow
   client-side revalidation.

## 3. Test Coverage

- System specs: assert `response.headers['Cache-Control']` contains `no-store` for each sensitive route.
- Back-button smoke test (patterned after `stripe_invoice_payment_system_spec.rb`).

## 4. CDN / Reverse-Proxy Notes

- Ensure our CDN (CloudFront, Fastly, etc.) respects `no-store` and does not override with its own caching rules.
- Add path-based rules to bypass cache for `/invoices/*`, `/orders/*`, `/bookings/*`, etc.

## 5. Security Considerations

- Prevents shoulder-surfing / shared device leakage of tokenised invoice/ order URLs.
- Eliminates possibility of "stale pending" pages encouraging duplicate payments.
- Headers **must not** be added to static marketing pages  ensure SEO unaffected.

## 6. Roll-out Checklist

- [ ] Implement `Public::BaseController` and migrate controllers.
- [ ] Add unit specs for new helper.
- [ ] Update system specs for each resource.
- [ ] Deploy to staging, verify back-button shows fresh data.
- [ ] Notify QA to run regression around payments/bookings.
- [ ] After production deploy, monitor logs for `Cache-Control` headers via CDN.

---
*Last updated: #{Time.now.strftime('%Y-%m-%d %H:%M %Z')}* 