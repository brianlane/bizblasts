# CNAME Custom Domain Implementation – Step-by-Step Todo

> **Scope**: Enable premium-tier businesses to connect a custom domain (via CNAME) to their BizBlasts site. This document tracks every required task across backend, jobs, UI, mailers, and documentation.  
> **Owner**: Engineering  
> **Last updated**: 08/21/2025

---

## 1. Database Changes

1. **Add columns to `businesses`**  
   `cname_setup_email_sent_at :datetime`  
   `cname_monitoring_active   :boolean , default: false, null: false`  
   `cname_check_attempts      :integer , default: 0,     null: false`  
   `render_domain_added       :boolean , default: false, null: false`
2. **Extend status/enum** – add: `cname_pending`, `cname_monitoring`, `cname_active`, `cname_timeout`.
3. Indexes on `status` and `cname_monitoring_active`.
4. Write migration + DB rollback test.

## 2. Model Enhancements (`Business`)

- Declare new enum values & validations.
- Scopes: `.cname_pending`, `.monitoring_needed`.
- Helper methods:  
  `start_cname_monitoring!`, `stop_cname_monitoring!`, `cname_due_for_check?`.
- Guard logic: Only allow on `premium_tier?` + `host_type_custom_domain?`.

## 3. Service Layer

| Service | Purpose |
|---------|---------|
| `CnameSetupService` | Kick-off flow: add domain in Render, send instructions email, mark `cname_pending`, activate monitoring |
| `RenderDomainService` | Low-level wrapper for Render REST API (`RENDER_API_KEY`, `RENDER_SERVICE_ID`) |
| `CnameDnsChecker` | Resolve CNAME & verify it points to Render |
| `DomainMonitoringService` | Coordinate retries & state transitions |

## 4. Background Job

- `DomainMonitoringJob` (Solid Queue): runs every 5 min on `Business.monitoring_needed`.
- Stops after **success** or **12 attempts (1 h)**.
- Manual restart resets attempt counter & re-enqueues.

## 5. Mailers

Templates in `DomainMailer`:
1. `setup_instructions` - note on the bottom for them to forward this email to ENV['SUPPORT_EMAIL'] if they need more assistance
2. `activation_success`
3. `timeout_help`
4. `monitoring_restarted`

## 6. Admin Interface

- ActiveAdmin → Businesses page:
  - “Send Domain Instructions” button.
  - Monitoring status panel.
  - Manual controls (restart / stop / force-activate).
- Optional AJAX JSON endpoints for live status.

## 7. Middleware / Routing

- Update tenant resolution middleware (& `TenantHost`) to accept hosts where `status == 'cname_active'`.
- Preserve existing subdomain logic.

## 8. Render.com Integration

- Store `RENDER_API_KEY`, `RENDER_SERVICE_ID` in `.env` (no Rails secrets).
- `RenderDomainService` wraps the **Render REST API** and exposes: `add_domain`, `verify_domain`, `list_domains`, `remove_domain`.
- **Key API endpoints** (all bearer-token authenticated):  
  • **Add domain** `POST /v1/services/{serviceId}/custom-domains`  
  • **Verify DNS** `POST /v1/services/{serviceId}/custom-domains/{domainId}/verify`  
  • **List domains** `GET /v1/services/{serviceId}/custom-domains`  
  • **Delete domain** `DELETE /v1/services/{serviceId}/custom-domains/{domainId}` (used on downgrade).  
- **Working Ruby example** (simplified):  
  ```ruby
  url = URI("https://api.render.com/v1/services/#{ENV['RENDER_SERVICE_ID']}/custom-domains")
  req = Net::HTTP::Post.new(url, {
    'Accept' => 'application/json',
    'Content-Type' => 'application/json',
    'Authorization' => "Bearer #{ENV['RENDER_API_KEY']}"
  })
  req.body = { name: custom_domain }.to_json
  response = Net::HTTP.start(url.hostname, url.port, use_ssl: true) { |h| h.request(req) }
  ```
- Render auto-issues & renews TLS certificates, performs HTTP→HTTPS redirect, and manages `www.` ↔ root redirects.
- Our monitoring loop polls **verify endpoint** until it returns `"verified": true`.

## 11. Downgrade / Domain Removal Logic

- **Trigger:** Business downgrades from Premium tier or chooses to disable custom domain.
- **Steps:**  
  1. Call `RenderDomainService#remove_domain` (DELETE endpoint).  
  2. Update `business` record: reset `host_type` to `subdomain`, clear `hostname`, stop monitoring flags.  
  3. Transition status back to `active` (subdomain) and send "Domain Removed" confirmation email.  
  4. Tenant middleware automatically falls back to subdomain routing.  
- **Admin UI:** “Disable Custom Domain” button with confirmation dialog.  (If needed for manual process)
- **Tests:** RSpec & system specs verifying removal flow and subdomain fallback.

## 9. Tests

- **Model / Migration**: enum, validations, scopes.
- **Service**: full happy path & edge cases (WebMock for Render + DNS).
- **Job**: respects attempt limit & state transitions.
- **System**: end-to-end flow (Capybara) – premium business connects domain, sees success.

## 10. Documentation & Ops

- Update README “Domain Architecture” section.
- Add `.env.example` variables (`RENDER_API_KEY`, `RENDER_SERVICE_ID`).
- Produce registrar-specific FAQ.

---

### Timeline / Milestones

| Week | Deliverable |
|------|-------------|
| 1 | DB migration, `Business` model updates, unit tests |
| 2 | Service layer (`CnameSetupService`, `RenderDomainService`) + mailer templates |
| 3 | Monitoring job + DNS checker; integrate Solid Queue |
| 4 | Admin UI & routing changes |
| 5 | System tests, documentation polish, staging rollout |

---

**Done-Checklist Template** (copy into PR description)

- [ ] Migration applied & reversible
- [ ] `Business` enum/tests updated
- [ ] Services implemented & 100% unit-tested
- [ ] Solid Queue job wired & tested
- [ ] Tenant middleware handles `cname_active`
- [ ] ActiveAdmin panel functional
- [ ] Mailer templates previewed
- [ ] README/docs updated
- [ ] All specs & linters pass
