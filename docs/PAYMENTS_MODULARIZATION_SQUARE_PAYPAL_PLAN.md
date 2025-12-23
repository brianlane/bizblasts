## Payments Modularization Plan (Stripe + Square + PayPal)

### Goals
- **Customer choice at checkout**: On invoice/order/tip/etc payment pages, the customer can choose **Stripe, Square, or PayPal**.
- **No provider-only flows**: No part of the product remains “Stripe-only” by design. If a provider cannot support a feature, the UI must either:
  - not offer that provider for that specific checkout context, **or**
  - offer it with a clearly defined fallback (e.g., “Pay later / offline”), but never silently force Stripe.
- **Modular, testable, secure**: Each provider is an implementation of the same contract, with consistent DB records and reconciliation.

### Current State (what exists today)
- **Stripe dominates the payments stack**:
  - Checkout initiation is server-side redirects via `StripeService`.
  - Webhook processing is Stripe-specific (`/webhooks/stripe`), with signature verification middleware and async job.
  - `Payment` table and many models embed Stripe IDs (`stripe_payment_intent_id`, `stripe_customer_id`, etc.).
  - Business settings UI is Stripe Connect only.
- **Payment flows that redirect to Stripe today**
  - Invoice payment
  - Order payment
  - Tip payment
  - Booking-related invoice payment
  - Client document deposits
  - Estimate deposits
  - Rental security deposits (supports preauth/capture)
  - Subscriptions (customer subscriptions + BizBlasts tier billing)

### Target Architecture (Provider-agnostic core + adapters)

#### 1) Domain concepts
- **PaymentAttempt** (new): A provider-neutral record representing “a checkout has been created and the customer is being sent to the provider.”
- **Payment** (existing): The “money moved” record, created/updated on webhook success/failure/refund.
- **Payable**: The thing being paid for (invoice/order/tip/rental booking/client document/etc.).

#### 2) Core services (new module)
Create `app/services/payments/` with:

- **`Payments::CheckoutContext`** (value object)
  - `business`, `tenant_customer` (optional for guest flows), `currency`
  - `payable` (polymorphic)
  - `amount_cents` (and optional split breakdown)
  - `success_url`, `cancel_url`
  - `metadata` (hash) for idempotency + later reconciliation

- **`Payments::Provider` interface** (contract)
  - `key` → symbol/string (`:stripe`, `:square`, `:paypal`)
  - `enabled_for?(business)`
  - `supported_contexts` (or `supports?(context)`)
  - `start_checkout!(context:)` → returns:
    - `redirect_url`
    - `external_checkout_id` (provider session/order/checkout id)
    - `provider_payload` (minimal non-sensitive)
  - `refund!(payment:, amount_cents: nil, reason: nil)`
  - `verify_webhook!(payload:, headers:)` → returns parsed event or raises
  - `handle_webhook!(event:)` → updates records (PaymentAttempt/Payment/Payable)

- **`Payments::Router`**
  - Input: `context`, plus optionally `provider_key` (customer-selected)
  - Output: provider + checkout result
  - Responsibilities:
    - Validate provider choice is enabled for business
    - Validate provider supports the specific context
    - Create `PaymentAttempt`
    - Ask provider to create checkout, persist external id
    - Return `redirect_url`

- **`Payments::Reconciler`**
  - Provider-agnostic reconciliation helpers:
    - Find tenant context reliably
    - Idempotently create/update `Payment`
    - Mark invoice/order states
    - Create business notifications

#### 3) Provider adapters
- **`Payments::Providers::Stripe`**
  - Initially delegates most logic to existing `StripeService` (adapter layer).
  - Over time, move Stripe-specific logic out of `StripeService` and into this adapter.

- **`Payments::Providers::Square`**
  - Uses Square APIs for:
    - OAuth connect
    - Creating checkout links/orders
    - Webhook processing
    - Refunds

- **`Payments::Providers::PayPal`**
  - Uses PayPal APIs for:
    - Partner onboarding/OAuth
    - Creating orders/checkout links
    - Webhook processing
    - Refunds

### Data Model Changes

#### 1) New table: `payment_attempts`
Purpose: represent a checkout session/order/link across providers.

Recommended fields:
- `business_id` (required)
- `tenant_customer_id` (nullable for guest flows if you support true guest)
- `payable_type`, `payable_id` (polymorphic)
- `provider` (string/enum): `stripe|square|paypal`
- `status` (enum): `created`, `redirected`, `succeeded`, `cancelled`, `failed`
- `amount_cents`, `currency`
- `external_checkout_id` (string)
- `idempotency_key` (string, unique)
- `metadata` (jsonb)
- timestamps

Indexes:
- `(provider, external_checkout_id)` unique
- `(business_id, created_at)`
- `(payable_type, payable_id)`

#### 2) Evolve existing table: `payments`
Goal: provider-neutral, while keeping Stripe columns temporarily during migration.

Add fields:
- `provider` (string/enum)
- `provider_payment_id` (string)
- `provider_charge_id` (string)
- `provider_customer_id` (string)
- `processor_fee_amount` (decimal)
- `processor_fee_currency` (string, optional)
- `provider_payload` (jsonb, optional)

Migration strategy:
- Keep existing `stripe_*` columns for now.
- Set `payments.provider='stripe'` for historical Stripe records.
- Gradually update code and UI to prefer provider-neutral columns.

#### 3) Business payment configuration
Add columns to `businesses`:
- `payment_providers_enabled` (jsonb array or bitmask; store `['stripe','square','paypal']`)
- `default_payment_provider` (string)
- Stripe: keep existing `stripe_account_id`, `stripe_customer_id`
- Square:
  - `square_merchant_id`
  - `square_location_id`
  - `square_access_token` (encrypted)
  - `square_refresh_token` (encrypted, if used)
- PayPal:
  - `paypal_merchant_id`
  - `paypal_access_token` (encrypted, if stored)
  - `paypal_refresh_token` (encrypted)
  - `paypal_environment` (`sandbox|live`)

Security:
- Store tokens using Rails encryption (Active Record Encryption), never plain text.

### Routing & Webhooks

#### 1) Public routes (customer-facing)
Today you have `payments#new` that redirects to Stripe.
Target:
- Allow provider selection:
  - `GET /payments/new?invoice_id=...&provider=stripe|square|paypal`
  - Or introduce a dedicated endpoint like `POST /checkout` (recommended) to avoid GET side effects.

Recommended:
- Keep GET for backward compatibility short-term.
- Add POST endpoint for new UI:
  - `POST /checkout` with params `{payable_type, payable_id, provider}`

#### 2) Webhook endpoints
Add:
- `POST /webhooks/square`
- `POST /webhooks/paypal`

Each should:
- Verify signature (middleware or controller)
- Enqueue async job
- Job calls provider adapter `verify_webhook!` + `handle_webhook!`

Tenant resolution:
- Stripe: already uses metadata and connected account id.
- Square: resolve via `merchant_id` / `location_id` in event.
- PayPal: resolve via merchant id in event.

### UI Changes (Customer chooses provider)

#### 1) Invoice page
Update invoice show page(s) to:
- Render **Pay buttons per enabled provider**:
  - “Pay with Card (Stripe)”
  - “Pay with Square”
  - “Pay with PayPal”
- Buttons call the same checkout creation endpoint with `provider` param.

Rules:
- Only show providers that are **enabled and connected** for the business.
- If a provider is enabled but not connected, show business-facing warnings only (never to customers).

#### 2) Order checkout
At the final step (after invoice/order created), show provider options or redirect immediately to the chosen provider.

Two valid UX patterns:
- **Pattern A (recommended)**: Choose provider on the checkout page before placing the order.
- **Pattern B**: Place order → show payment page that lets user pick provider.

Given your current flow auto-redirects to Stripe after order creation, implement Pattern A by:
- Adding a “Payment method” section (Stripe/Square/PayPal)
- Pass selected provider through to controller so it creates checkout with that provider.

#### 3) Tips
Tips are currently token-based and redirect directly to Stripe.
- Add provider choice similarly, but note:
  - If PayPal/Square cannot support the same tip flow constraints, do not display it.

### Refunds & Provider Capability Differences

#### Capabilities table
Define a simple capability map per provider:
- One-time payment
- Partial refunds
- Authorization + capture (required for rental deposit preauth)
- Subscriptions

Policy:
- For a given checkout context, the router only offers providers that support the required capabilities.
- This satisfies “Nothing remains only Stripe” by ensuring the system is not hardcoded to Stripe; it may still be true that only a subset of providers support a subset of contexts, but that’s a capability constraint, not a design constraint.

### Subscription Strategy (important)
You currently have two subscription families:
- **Customer subscriptions** (product/service subscriptions for a tenant)
- **BizBlasts tier billing** (business registration and plan billing)

Target:
- Implement provider-neutral subscription interfaces.
- For providers that don’t support your exact subscription semantics, disable them for that context.

Implementation approach:
- Introduce `Billing::Provider` (separate from checkout payments) or fold into Payments provider with `supports_subscriptions?`.
- Add a business-level configuration for “platform billing provider” (which can differ from customer checkout provider).

### Implementation Steps (no-code sequence)

#### Phase 0 — Baseline inventory and guardrails
- Write provider capability matrix for every payment context:
  - invoice/order payment
  - tips
  - booking payments
  - estimate deposits
  - client document deposits
  - rental deposits (preauth/capture)
  - customer subscriptions
  - BizBlasts tier billing

#### Phase 1 — Introduce provider-neutral core (Stripe adapter first)
- Add `payment_attempts` table
- Add provider-neutral fields to `payments`
- Implement `Payments::Router` and `Payments::Providers::Stripe` adapter (delegating to `StripeService`)
- Update controllers to call router
- Keep behavior identical for Stripe to maintain stability

#### Phase 2 — Add Square provider
- Business connect flow (OAuth) + store tokens encrypted
- Implement Square checkout creation
- Implement Square webhook verification + handling
- Implement refunds
- Add UI buttons for Square
- Add tests + webhook helpers

#### Phase 3 — Add PayPal provider
- Business connect flow (Partner/OAuth) + store tokens encrypted
- Implement PayPal checkout creation
- Implement PayPal webhook verification + handling
- Implement refunds
- Add UI buttons for PayPal
- Add tests + webhook helpers

#### Phase 4 — Provider-neutralize the domain layer
- Remove direct calls to `StripeService` from non-provider code
- Move Stripe-specific logic into Stripe provider adapter
- Update UI labels to show provider and show “processor fee” rather than “Stripe fee”

#### Phase 5 — Subscriptions parity
- Implement provider-neutral subscription contract
- Add Square/PayPal subscription support if feasible; otherwise gate by capability
- Ensure platform tier billing and customer subscriptions both support user choice where applicable

### Test Plan

#### Unit tests
- `Payments::Router`:
  - rejects disabled providers
  - rejects unsupported context
  - creates `PaymentAttempt` and persists external ids
- Provider adapters:
  - request building and success parsing
  - refund routing

#### Request specs
- `/checkout` creates a redirect for each provider
- `/webhooks/:provider` signature verification and job enqueue

#### System specs
- Invoice pay page shows provider options
- Selecting Square/PayPal redirects to correct provider URL (mocked)
- Simulated webhook marks invoice/order paid and creates `Payment`

### Security & Compliance
- All webhook endpoints must verify signatures.
- All provider tokens must be encrypted at rest.
- Log sanitization: never log raw tokens or full webhook payloads containing sensitive fields.

### Operational Considerations
- Provider sandbox/live environment handling:
  - Stripe test vs live
  - Square sandbox vs production
  - PayPal sandbox vs live
- Admin tooling:
  - Show provider connection status per business
  - Show last webhook receipt per provider

### Acceptance Criteria
- Customer can choose Stripe/Square/PayPal at checkout (invoice/order/tip/other flows as applicable).
- Webhooks for all providers reconcile payments correctly (idempotent) and update domain objects.
- Refunds work for all providers where supported.
- No domain code calls provider SDKs directly (only provider adapters).
- Tests cover provider selection and webhook reconciliation.


