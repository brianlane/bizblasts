# Client Path Refactor - TODO

## Overview

Refactor all client-related paths to be prefixed with `/client` to match the pattern used for business managers (`/manage`) and admins (`/admin`). This will simplify authentication to only 3 protected path prefixes.

## Goals

1. **Role-based path restrictions:**
   - `client` role → Can only access `/client/*` + public endpoints
   - `manager`/`staff` roles → Can only access `/manage/*` + public endpoints
   - `admin` role → Can only access `/admin/*` + public endpoints

2. **Simplified authentication:**
   - Current: 11 protected paths to maintain
   - After: 3 protected prefixes (`/client`, `/manage`, `/admin`)

3. **Eliminate dual endpoint complexity:**
   - No more confusion between public and client-specific endpoints
   - Clear separation: `/client/bookings` (user's personal data) vs `/bookings` (public booking form)

4. **Wrong namespace access behavior:**
   - Client user attempts `/manage/*` → 403 Forbidden or redirect to `/client/dashboard` with error message
   - Manager user attempts `/client/*` → 403 Forbidden or redirect to `/manage/dashboard` with error message
   - Admin user attempts `/client/*` or `/manage/*` → Access their own `/admin/*` area
   - All unauthorized attempts logged for security monitoring

## Path Mapping

### Current → New

| Current Path | New Path | Controller |
|-------------|----------|------------|
| `/dashboard` | `/client/dashboard` | Client::DashboardController |
| `/my-bookings` | `/client/my-bookings` | Client::BookingsController |
| `/my-bookings/:id/cancel` | `/client/my-bookings/:id/cancel` | Client::BookingsController |
| `/invoices` | `/client/invoices` | Client::InvoicesController |
| `/invoices/:id/pay` | `/client/invoices/:id/pay` | Client::InvoicesController |
| `/transactions` | `/client/transactions` | Client::TransactionsController |
| `/settings` | `/client/settings` | Client::SettingsController ✓ |
| `/settings/unsubscribe_all` | `/client/settings/unsubscribe_all` | Client::SettingsController ✓ |
| `/subscriptions` | `/client/subscriptions` | Client::SubscriptionsController ✓ |
| `/subscriptions/:id/cancel` | `/client/subscriptions/:id/cancel` | Client::SubscriptionsController ✓ |
| `/subscriptions/:id/preferences` | `/client/subscriptions/:id/preferences` | Client::SubscriptionsController ✓ |
| `/subscription_loyalty` | `/client/subscription_loyalty` | Client::SubscriptionLoyaltyController ✓ |
| `/subscription_loyalty/tier_progress` | `/client/subscription_loyalty/tier_progress` | Client::SubscriptionLoyaltyController ✓ |
| `/subscription_loyalty/milestones` | `/client/subscription_loyalty/milestones` | Client::SubscriptionLoyaltyController ✓ |
| `/settings/subscriptions` | `/client/settings/subscriptions` | Client::SettingsController ✓ |
| `/settings/update_subscriptions` | `/client/settings/update_subscriptions` | Client::SettingsController ✓ |

✓ = Already in Client:: namespace, just needs route path fix

### Additional Paths to Verify

Check for these potential client paths that may exist:
- [ ] `/loyalty_cards` → `/client/loyalty_cards` (if exists)
- [ ] `/notifications` → `/client/notifications` (if exists)
- [ ] `/preferences` → `/client/preferences` (if exists)
- [ ] `/profile` → `/client/profile` (if exists)
- [ ] Any feature-flagged or beta routes under client context

## Tasks

### 1. Controller Refactoring

- [ ] **Create Client::BaseController**
  - File: `app/controllers/client/base_controller.rb`
  - Add `before_action :authenticate_user!`
  - Add `before_action :require_client_role`
  - Add `skip_before_action :verify_authenticity_token, if: -> { request.format.json? }` (if JSON endpoints exist)
  - Include `Pundit::Authorization` if using policy enforcement
  - Add `after_action :verify_authorized, except: [:index]` if using Pundit
  - Add `rescue_from Pundit::NotAuthorizedError` handler
  - All client controllers will inherit from this

- [ ] **Ensure Devise controllers inherit properly**
  - [ ] Verify `client/registrations_controller.rb` inherits from `Devise::RegistrationsController`
  - [ ] Confirm Devise routes are under `/client` namespace (e.g., `/client/sign_in`, `/client/sign_up`)
  - [ ] Update `config/routes.rb` Devise configuration if needed:
    ```ruby
    devise_for :users, path: 'client', controllers: {
      registrations: 'client/registrations'
    }
    ```

- [ ] **Move and rename controllers:**
  - [ ] `client_dashboard_controller.rb` → `client/dashboard_controller.rb`
    - Rename class from `ClientDashboardController` to `Client::DashboardController`
    - Change to inherit from `Client::BaseController`

  - [ ] `client_bookings_controller.rb` → `client/bookings_controller.rb`
    - Rename class from `ClientBookingsController` to `Client::BookingsController`
    - Change to inherit from `Client::BaseController`

  - [ ] `invoices_controller.rb` → `client/invoices_controller.rb`
    - Rename class from `InvoicesController` to `Client::InvoicesController`
    - Change to inherit from `Client::BaseController`

  - [ ] `transactions_controller.rb` → `client/transactions_controller.rb`
    - Rename class from `TransactionsController` to `Client::TransactionsController`
    - Change to inherit from `Client::BaseController`

- [ ] **Update existing Client:: controllers to inherit from Client::BaseController:**
  - [ ] `client/settings_controller.rb`
  - [ ] `client/subscriptions_controller.rb`
  - [ ] `client/subscription_loyalty_controller.rb`
  - [ ] `client/registrations_controller.rb`

- [ ] **Delete old controller files after moving:**
  - [ ] Delete `app/controllers/client_dashboard_controller.rb`
  - [ ] Delete `app/controllers/client_bookings_controller.rb`
  - [ ] Delete `app/controllers/invoices_controller.rb`
  - [ ] Delete `app/controllers/transactions_controller.rb`

- [ ] **Check for references to old controller class names:**
  - [ ] Search background jobs for references (e.g., `ClientDashboardController`)
  - [ ] Search mailers for controller references
  - [ ] Search lib/ directory for hardcoded controller names
  - [ ] Search config/ directory for controller references
  - [ ] Run: `grep -r "ClientDashboardController\|ClientBookingsController\|InvoicesController\|TransactionsController" app/ lib/ config/`

### 2. Routes Refactoring

- [ ] **config/routes.rb - Consolidate all client routes under `/client` namespace**
  - [ ] Remove individual client routes (lines ~617-670)
  - [ ] Remove `namespace :client, path: ''` (this was defeating the purpose)
  - [ ] Remove duplicate `resources :settings` block (lines ~664-669) that contains JSON helpers
  - [ ] Create consolidated `namespace :client do` block with all routes:
    ```ruby
    namespace :client do
      get 'dashboard', to: 'dashboard#index', as: :dashboard

      resources :bookings, path: 'my-bookings' do
        member do
          patch 'cancel'
        end
      end

      resources :invoices, only: [:index, :show] do
        member do
          post 'pay'
        end
      end

      resources :transactions, only: [:index, :show]

      resource :settings, only: [:show, :edit, :update, :destroy] do
        patch :unsubscribe_all, on: :member
        get :subscriptions, on: :collection
        patch :update_subscriptions, on: :collection
      end

      resources :subscriptions, only: [:index, :show, :edit, :update] do
        member do
          get :cancel
          post :cancel
          get :preferences
          patch :update_preferences
          get :billing_history
        end
      end

      resources :subscription_loyalty, only: [:index, :show] do
        member do
          post :redeem_points
        end
        collection do
          get :tier_progress
          get :milestones
        end
      end
    end
    ```

- [ ] **Update subdomain settings redirect (line ~521)**
  - Current: Redirects to `/settings`
  - New: Redirect to `/client/settings`

- [ ] **Devise routes configuration**
  - [ ] Verify Devise routes are properly namespaced under `/client`
  - [ ] Confirm login URL is `/client/sign_in` (not `/users/sign_in`)
  - [ ] Confirm signup URL is `/client/sign_up` (not `/users/sign_up`)
  - [ ] Update `devise_for :users` configuration in routes.rb
  - [ ] If Devise routes remain at `/users/*`, document why and ensure consistency

- [ ] **API routes (if applicable)**
  - [ ] Check if any JSON API endpoints serve client data (e.g., `/api/v1/client/*`)
  - [ ] Decide if API routes change or remain unchanged
  - [ ] Document: "API routes remain at `/api/v1/*` and handle client data via authentication"
  - [ ] Update API controller namespaces if needed

- [ ] **Legacy URL handling**
  - [ ] **Decision:** Old URLs will return 404 (no backwards compatibility)
  - [ ] Remove any existing redirects from old paths
  - [ ] Document this decision for team/stakeholders
  - [ ] Monitor 404s in production after deployment

- [ ] **Rate-limited or feature-flagged routes**
  - [ ] Check for beta routes like `/beta/loyalty_stats`
  - [ ] Verify feature-flagged controllers are properly namespaced
  - [ ] Update Flipper/feature flag configurations if path-dependent

### 3. View Directory Refactoring

- [ ] **Move view directories:**
  - [ ] `app/views/client_dashboard/` → `app/views/client/dashboard/`
  - [ ] `app/views/client_bookings/` → `app/views/client/bookings/`
  - [ ] `app/views/invoices/` → `app/views/client/invoices/`
  - [ ] `app/views/transactions/` → `app/views/client/transactions/`
  - [ ] `app/views/client/settings/` ✓ (already correct)
  - [ ] `app/views/client/subscriptions/` ✓ (already correct)
  - [ ] `app/views/client/subscription_loyalty/` ✓ (already correct)

- [ ] **Update mailer views with client path references:**
  - [ ] Search mailer templates for client path URLs: `grep -r "dashboard_path\|invoices_path\|settings_path" app/views/mailers app/views/*_mailer`
  - [ ] Update email templates to use new path helpers (e.g., `client_dashboard_path`)
  - [ ] Common mailers to check:
    - [ ] User welcome emails
    - [ ] Booking confirmation emails
    - [ ] Invoice/payment emails
    - [ ] Subscription update emails
    - [ ] Password reset emails (if they link to dashboard)

### 4. Path Helper Updates

Update all references from old path helpers to new ones:

- [ ] **dashboard_path → client_dashboard_path**
  - [ ] `app/controllers/application_controller.rb` (line 297, 335)
  - [ ] `app/views/policy_acceptances/show.html.erb`
  - [ ] Any other references

- [ ] **client_bookings_path → client_bookings_path** (stays same but verify context)
  - [ ] `app/views/client/dashboard/index.html.erb`

- [ ] **invoices_path → client_invoices_path**
  - [ ] `app/views/client/invoices/show.html.erb`
  - [ ] Any other references

- [ ] **transactions_path → client_transactions_path**
  - [ ] `app/views/client/dashboard/index.html.erb`
  - [ ] `app/views/client/invoices/show.html.erb`
  - [ ] Any other references

- [ ] **settings_path → client_settings_path**
  - Search all views and controllers

- [ ] **Search for all occurrences:**
  ```bash
  grep -r "dashboard_path\|invoices_path\|transactions_path\|settings_path" app/views app/controllers
  ```

- [ ] **JavaScript and Stimulus controller updates:**
  - [ ] Search for path references in JavaScript files:
    ```bash
    grep -r "dashboard\|invoices\|transactions\|settings" app/javascript --include="*.js"
    ```
  - [ ] Check Stimulus controllers using data-attributes with paths:
    - Look for `data-url`, `data-path`, `data-redirect-path` attributes
  - [ ] Update any `window.location =` or `Turbo.visit()` calls with old paths
  - [ ] Check for route generation in JavaScript (if using Rails routes in JS)

- [ ] **React/Vue component updates (if applicable):**
  - [ ] Search React components for hardcoded client paths
  - [ ] Update any `<Link to="">` or routing configuration
  - [ ] Check for API endpoints that return client URLs in JSON

### 5. Configuration Updates

- [ ] **config/application.rb - Simplify auth_required_paths**
  - Current (lines 57-70): 11 paths
  - New: Only 3 paths
  ```ruby
  config.x.auth_required_paths = [
    '/client',  # All client user routes
    '/manage',  # All business manager routes
    '/admin'    # All admin routes
  ]
  ```

- [ ] **Update fallback defaults in application_controller.rb (line 558-562)**
  ```ruby
  auth_required_paths = ['/client', '/manage', '/admin']
  ```

- [ ] **Middleware configuration updates**
  - [ ] **Rack::Attack rate limiting:** Update any path-based rate limits in `config/initializers/rack_attack.rb`
  - [ ] **Flipper feature flags:** Update any feature flag configurations that depend on paths
  - [ ] **Any custom middleware** that whitelists or processes specific paths
  - [ ] Search middleware configs: `grep -r "/dashboard\|/invoices\|/transactions\|/settings" config/initializers/`

### 6. Test Updates

- [ ] **Update request specs:**
  - [ ] `spec/requests/client/settings_spec.rb`
  - [ ] `spec/requests/client/client_bookings_spec.rb`
  - [ ] `spec/requests/client/registrations_spec.rb`
  - [ ] `spec/requests/client/settings_deletion_spec.rb`
  - [ ] Create new specs for:
    - [ ] `spec/requests/client/dashboard_spec.rb`
    - [ ] `spec/requests/client/invoices_spec.rb`
    - [ ] `spec/requests/client/transactions_spec.rb`

- [ ] **Update system specs:**
  - [ ] `spec/system/client/settings_management_spec.rb`
  - [ ] `spec/system/client/account_deletion_spec.rb`
  - [ ] Any other client-related system tests

- [ ] **Update controller specs:**
  - [ ] `spec/controllers/client/subscriptions_controller_spec.rb`
  - [ ] Create new specs for moved controllers

- [ ] **Additional test scenarios:**
  - [ ] **Cross-namespace access tests:**
    - [ ] Test client user accessing `/manage/*` → 403 Forbidden
    - [ ] Test manager user accessing `/client/*` → 403 Forbidden
    - [ ] Test admin user accessing `/client/*` and `/manage/*` → appropriate access
  - [ ] **Legacy URL tests:**
    - [ ] Test old URLs return 404 (e.g., `/dashboard`, `/invoices`)
    - [ ] Verify no accidental redirects from old paths
  - [ ] **JSON and Turbo Stream variants:**
    - [ ] Test JSON endpoints with new paths
    - [ ] Test Turbo Stream responses work correctly
    - [ ] Test AJAX requests to new client endpoints
  - [ ] **Authentication flow tests:**
    - [ ] Test login redirects to `/client/dashboard`
    - [ ] Test `store_location_for` saves client paths correctly
    - [ ] Test after_sign_in_path_for routes to client namespace

### 7. ApplicationController Updates

- [ ] **Update redirect logic in `user_not_authorized` (line 296-297)**
  - Change `redirect_to dashboard_path` to `redirect_to client_dashboard_path`

- [ ] **Update `after_sign_in_path_for` (line 334-335)**
  - Change `dashboard_path` to `client_dashboard_path`

- [ ] **Update `requires_authentication?` method** (optional - will be simplified by config change)

- [ ] **Update Devise location storage logic**
  - [ ] Ensure `store_location_for` saves client paths correctly
  - [ ] Verify Devise redirects after sign-in go to `/client/*` paths
  - [ ] Test that stored locations work with namespace changes
  - [ ] Update any custom `stored_location_for` logic if present

### 8. Public vs Client Controller Clarity

Ensure these remain separate and correctly scoped:

- [ ] **Public controllers (tenant context):**
  - `app/controllers/public/client_bookings_controller.rb` - For viewing bookings on business subdomain
  - `app/controllers/public/invoices_controller.rb` - For viewing invoices on business subdomain
  - `app/controllers/public/transactions_controller.rb` - For viewing transactions on business subdomain

- [ ] **Client controllers (main domain, user's personal data):**
  - `app/controllers/client/bookings_controller.rb` - User's bookings across all businesses
  - `app/controllers/client/invoices_controller.rb` - User's invoices across all businesses
  - `app/controllers/client/transactions_controller.rb` - User's transactions across all businesses

- [ ] **Verify policy scope differences:**
  - [ ] Confirm `Public::` controllers use tenant-scoped policies (data for current business only)
  - [ ] Confirm `Client::` controllers use user-scoped policies (user's data across all businesses)
  - [ ] Update policy scopes if they don't properly differentiate between contexts
  - [ ] Example: `Public::InvoicesController` shows invoices for current tenant, `Client::InvoicesController` shows user's invoices across all tenants

### 9. Dashboard Controller Cleanup

- [ ] **Update `dashboard_controller.rb`** (currently routes to client dashboard)
  - Remove or refactor this file - it's now redundant with Client::DashboardController
  - Or keep it as a simple router that redirects based on role

### 10. Policies

- [ ] **Check/update Pundit policies:**
  - [ ] `app/policies/client/settings_policy.rb`
  - [ ] Create policies for other client resources if needed
  - [ ] **Ensure ApplicationPolicy defaults forbid cross-namespace access:**
    - [ ] Update ApplicationPolicy to deny access by default
    - [ ] Require explicit policy definitions for each namespace
    - [ ] Add role-based checks in base policy
  - [ ] **Verify Client::BaseController calls authorize/policy_scope:**
    - [ ] Add `after_action :verify_authorized` to Client::BaseController
    - [ ] Add `after_action :verify_policy_scoped` for index actions
    - [ ] Add `rescue_from Pundit::NotAuthorizedError` handler
  - [ ] **Create namespace-specific policies:**
    - [ ] Client::DashboardPolicy
    - [ ] Client::BookingPolicy
    - [ ] Client::InvoicePolicy
    - [ ] Client::TransactionPolicy

### 11. Additional Hidden Touchpoints

- [ ] **Background Jobs generating client links:**
  - [ ] Search jobs for client path generation: `grep -r "dashboard_path\|invoices_path\|settings_path" app/jobs/`
  - [ ] Common jobs to check:
    - [ ] Invoice reminder emails
    - [ ] Booking confirmation emails
    - [ ] Welcome email jobs
    - [ ] Subscription notification jobs
    - [ ] Password reset emails linking to dashboard
  - [ ] Update job templates to use new client path helpers

- [ ] **ActiveStorage and Blob URLs:**
  - [ ] Check if any signed URLs redirect to client controllers
  - [ ] Verify blob download/view routes work with new namespace
  - [ ] Update any custom ActiveStorage routes if they redirect to `/client/*`

- [ ] **ActionCable channels:**
  - [ ] Search for path references in channels: `grep -r "dashboard\|invoices\|settings" app/channels/`
  - [ ] Update any subscription identifiers that reference old paths
  - [ ] Verify real-time updates work with new client paths

- [ ] **Admin impersonation feature (if present):**
  - [ ] Ensure impersonated client users route correctly to `/client/dashboard`
  - [ ] Update impersonation logic to use new client paths
  - [ ] Test impersonation flow with new namespace

- [ ] **Breadcrumbs, meta-tags, and SEO:**
  - [ ] Update breadcrumb helpers to use new client paths
  - [ ] Update meta-tag generators (canonical URLs, og:url, etc.)
  - [ ] Update sitemap generation if it includes client paths
  - [ ] Update any SEO-related path generation

- [ ] **i18n translation keys:**
  - [ ] Search translation files for path references: `grep -r "dashboard\|invoices\|settings" config/locales/`
  - [ ] Update any translation keys that reference old path helpers
  - [ ] Update URL text in translation files

- [ ] **Third-party integrations:**
  - [ ] Check webhook configurations that might reference client URLs
  - [ ] Update OAuth redirect URIs if they point to client paths
  - [ ] Verify payment processor redirect URLs (Stripe success/cancel URLs)
  - [ ] Update any external service configurations with client URLs

### 12. Final Verification

- [ ] **Run all tests:**
  ```bash
  bundle exec rspec
  ```

- [ ] **Check routes:**
  ```bash
  bundle exec rails routes | grep client
  ```

- [ ] **Verify authentication works for all 3 role types:**
  - [ ] Test client user can only access `/client/*`
  - [ ] Test manager user can only access `/manage/*`
  - [ ] Test admin user can only access `/admin/*`
  - [ ] Test all can access public routes (no prefix)

- [ ] **Manual testing checklist:**
  - [ ] Client login → redirects to `/client/dashboard`
  - [ ] Client can view `/client/my-bookings`
  - [ ] Client can view `/client/invoices`
  - [ ] Client can view `/client/transactions`
  - [ ] Client can access `/client/settings`
  - [ ] Client can access `/client/subscriptions`
  - [ ] Client cannot access `/manage/*` or `/admin/*`
  - [ ] Manager login → redirects to `/manage/dashboard`
  - [ ] Manager cannot access `/client/*` or `/admin/*`
  - [ ] Public users can access public endpoints

## Benefits After Completion

✅ **Authentication simplified:** Only 3 path prefixes to protect instead of 11
✅ **Clear role boundaries:** Each role has its own namespace
✅ **Reduced dual endpoint confusion:** Clear separation of public vs authenticated endpoints
✅ **Easier maintenance:** Single source of truth for client routes
✅ **Better security:** Defense-in-depth with clear role-based access control
✅ **Consistent patterns:** Mirrors `/manage` and `/admin` structure

## Notes

- **No backwards compatibility needed:** Old URLs can break (per user request)
- **Public endpoints remain unchanged:** `/services`, `/bookings` (booking form), etc. are still public
- **Tenant-scoped public controllers remain unchanged:** `public/client_bookings_controller.rb` etc.
- **Main domain vs subdomain clarity:**
  - `/client/*` routes only work on main domain
  - `/manage/*` routes only work on business subdomain/custom domain
  - Public routes work on both

## Estimated Time

- Controller refactoring: 2-3 hours
- Routes refactoring: 1 hour
- View updates: 2-3 hours
- Path helper updates: 2-3 hours
- Test updates: 3-4 hours
- Verification: 1-2 hours

**Total: ~12-16 hours**

## Risk Assessment

**Low Risk:**
- Controllers are already well-structured
- Tests exist for most functionality
- Clear namespace separation

**Medium Risk:**
- Large number of path helper updates
- Need to ensure public vs client controllers remain separate

**Mitigation:**
- Comprehensive test coverage
- Manual testing checklist
- Code review before merge

## Deployment Strategy & Risk Mitigation

### Rollback Plan

- [ ] **Feature flag preparation:**
  - [ ] Consider implementing feature flag to toggle between old/new namespaces
  - [ ] Prepare quick rollback script if needed
  - [ ] Document rollback procedure

- [ ] **Database backup:**
  - [ ] Ensure recent database backup before deployment
  - [ ] No schema changes required, but session data may be affected

### Deployment Steps Ordering

1. **Pre-deployment preparation:**
   - [ ] Merge all controller/view changes
   - [ ] Update all path helpers in views/mailers
   - [ ] Update configuration files

2. **Route deployment:**
   - [ ] Deploy route changes first (maintains old URL 404s)
   - [ ] Verify new routes work correctly
   - [ ] Test authentication flows

3. **Link updates:**
   - [ ] Deploy UI link updates
   - [ ] Update email templates
   - [ ] Update background job templates

4. **Monitoring setup:**
   - [ ] Set up 404 monitoring on old URLs
   - [ ] Monitor client authentication flows
   - [ ] Monitor error rates in client namespace

### Post-Deployment Monitoring

- [ ] **404 monitoring:**
  - [ ] Monitor for 404 spikes on old client URLs
  - [ ] Set up alerts for unusual 404 patterns
  - [ ] Track `/dashboard`, `/invoices`, `/transactions`, `/settings` 404s

- [ ] **Authentication flow monitoring:**
  - [ ] Monitor login success rates
  - [ ] Monitor redirect loops or authentication failures
  - [ ] Track client namespace access patterns

- [ ] **Performance monitoring:**
  - [ ] Monitor response times for new client routes
  - [ ] Check for any performance regressions
  - [ ] Monitor database query patterns

- [ ] **User behavior tracking:**
  - [ ] Track client users navigating to new paths
  - [ ] Monitor support tickets for navigation issues
  - [ ] Track client feature usage patterns

### Communication Plan

- [ ] **Internal team notification:**
  - [ ] Notify support team of URL changes
  - [ ] Update internal documentation
  - [ ] Prepare FAQ for common questions

- [ ] **User communication (if needed):**
  - [ ] Since no backwards compatibility, users may notice URL changes
  - [ ] Prepare explanation if users report "broken bookmarks"
  - [ ] Update any user-facing documentation with new URLs

---

## Review Notes: Potential Holes / Issues + “Is this worth doing?”

This section captures concerns and improvements discovered during review of this plan.

### High-Risk / Easy-to-Miss Issues

#### 1) Devise under `/client/*` vs “all `/client` requires auth”

If the app uses `config.x.auth_required_paths` (or similar middleware logic) to enforce authentication for the `/client` prefix, then moving Devise routes under `/client` can create **redirect loops**:

- `/client/sign_in` is itself under `/client` → app requires auth → redirects to sign-in → loop

**Mitigation options:**

- **Allowlist Devise endpoints** under `/client` so they remain reachable unauthenticated (e.g. `/client/sign_in`, `/client/sign_out`, `/client/sign_up`, `/client/password/*`, `/client/confirmation/*`, `/client/unlock/*` depending on enabled Devise modules).
- Or keep Devise routes on `/users/*` and redirect users into `/client/*` after login.

Also verify non-HTML formats (Turbo, JSON) don’t accidentally get forced into the same loop.

#### 2) Stored-location / return-to values can send users to legacy URLs

Even with “no backwards compatibility,” Devise’s `stored_location_for(resource)` (or custom redirect logic) can route users to whatever URL they last tried to access. If that stored location is a legacy path like `/dashboard`, they can hit **404 immediately after login**.

**Mitigation:**

- Normalize stored locations: map legacy client URLs to new equivalents (e.g. `/dashboard` → `/client/dashboard`, `/settings` → `/client/settings`), or ignore legacy stored locations and fall back to `/client/dashboard`.

#### 3) `subscription_loyalty` route shape: `resources` likely mismatches usage

The mapping implies a single, non-ID-based “my loyalty” area:

- `/subscription_loyalty`
- `/subscription_loyalty/tier_progress`
- `/subscription_loyalty/milestones`

But the proposed routes use `resources :subscription_loyalty` + `:show` + `member` actions, which implies IDs and helpers like `client_subscription_loyalty_path(:id)`.

**Mitigation:**

- If it is a single “my loyalty” dashboard, prefer **`resource :subscription_loyalty` (singular)** or explicit `get` routes with `controller: :subscription_loyalty`.
- Re-check existing controller/actions before locking the route structure.

#### 4) CSRF: skipping `verify_authenticity_token` based on JSON format is risky

`skip_before_action :verify_authenticity_token, if: -> { request.format.json? }` can be a security footgun when session cookies are used, because browsers can still send requests that look like JSON.

**Mitigation:**

- Only disable CSRF in controllers that are intentionally API-style and use a deliberate auth strategy (token auth, or `protect_from_forgery with: :null_session` in the appropriate place), not just based on format.

#### 5) Pundit verification hooks can break Devise + “render-only” pages

Adding `after_action :verify_authorized` / `verify_policy_scoped` in `Client::BaseController` can cause widespread failures unless every action calls `authorize` / `policy_scope`. It also tends to conflict with Devise controllers.

**Mitigation:**

- Make these verifications **opt-in** per controller, or add clear `skip_after_action` exceptions for Devise and any “static render” actions.

#### 6) Prefix matching pitfalls

Ensure “protect `/client`” checks are boundary-aware so `/client` does not match `/clientele`, etc. Also confirm handling for `/client` vs `/client/`.

#### 7) Domain constraints are stated but may not be enforced

Notes claim:

- `/client/*` only works on main domain
- `/manage/*` routes only work on business subdomain/custom domain

Make sure `routes.rb` or request constraints actually enforce this; otherwise you can wind up with confusing (or unsafe) cross-domain availability.

#### 8) Rollout ordering: “routes first” can break navigation

This plan says “no backwards compatibility” and suggests deploying route changes first. If views/mailers/jobs still generate old links, this creates a window of widespread 404s.

**Mitigation:**

- Prefer an **atomic deploy** (routes + helpers + views + mailers/jobs) OR
- Ship link/helper updates first, then remove old routes in a follow-up deploy (even if you never add redirects).

### Benefit Assessment: Is there real value in doing this whole plan?

Yes, if the goal is “path-prefix = role boundary,” there are real benefits:

- **Security/authorization simplicity:** collapsing many protected paths down to **3 prefixes** (`/client`, `/manage`, `/admin`) reduces “forgot to protect a route” risk.
- **Clarity:** a predictable URL structure makes it obvious what is client vs manager vs admin vs public, and makes it harder to confuse “public booking form” vs “client personal data.”
- **Auditing/monitoring:** wrong-namespace access becomes easier to detect and log consistently.
- **Future maintenance:** new client pages inherit protection by location, reducing ongoing overhead.

When it may not be worth it:

- If the app already relies on strong controller/policy enforcement and `auth_required_paths` is not a meaningful control, then this becomes a **high-churn refactor** with limited payoff.
- If “no backwards compatibility” materially impacts users (bookmarks, emailed links, stored redirect targets), the **support/UX cost** may outweigh the engineering benefit unless the current approach is already painful.

### Suggested Plan Tweaks (Recommended)

- Add a specific task: **decide Devise path strategy** (under `/client` with allowlist vs keep `/users/*`).
- Add a specific task: **normalize stored locations** so legacy paths don’t redirect users to 404 after login.
- Add a specific task: **confirm actual route shape** for loyalty (singular vs ID-based) and update the proposed routes accordingly.
- Replace JSON-format CSRF skipping with a **deliberate API pattern** (or explicitly document why skipping is safe in this app).
- Make Pundit verification hooks **opt-in or carefully excluded** for Devise/static pages.
- Update deployment strategy to avoid “routes first” breaking navigation during rollout.
