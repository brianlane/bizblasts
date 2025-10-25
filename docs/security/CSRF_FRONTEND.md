# Frontend CSRF Token Handling

## Overview

This document explains how CSRF (Cross-Site Request Forgery) protection works in our Rails application, particularly for AJAX requests from JavaScript.

## How CSRF Protection Works

### Rails Side

Rails includes CSRF protection by default through the `protect_from_forgery` method in `ApplicationController`. This protection:

1. Generates a unique CSRF token for each user session
2. Embeds this token in the HTML as a meta tag
3. Verifies the token on all non-GET requests
4. Raises `ActionController::InvalidAuthenticityToken` if the token is missing or invalid

### Frontend Side

For AJAX requests to work with CSRF protection, the frontend must include the CSRF token in the request headers.

## Implementation Pattern

### 1. CSRF Token in HTML

The CSRF token is embedded in the HTML `<head>` by Rails:

```html
<meta name="csrf-token" content="<%= form_authenticity_token %>">
```

This is automatically included in our application layout (`app/views/layouts/application.html.erb`).

### 2. JavaScript Helper Method

All JavaScript modules that make AJAX requests should use this pattern to retrieve the CSRF token:

```javascript
getCSRFToken() {
  const token = document.querySelector('meta[name="csrf-token"]');
  return token ? token.getAttribute('content') : '';
}
```

**Example:** See `app/javascript/modules/promo_code_handler.js:220-223`

### 3. Including CSRF Token in AJAX Requests

When making POST/PUT/PATCH/DELETE requests via `fetch()`, always include the CSRF token in headers:

```javascript
fetch('/api/endpoint', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': this.getCSRFToken()  // ← Required!
  },
  body: JSON.stringify({ data: 'value' })
})
```

**Example:** See `app/javascript/modules/promo_code_handler.js:63-73`

## Real-World Examples

### Promo Code Validation (Public::OrdersController)

**Backend:** `app/controllers/public/orders_controller.rb`
- The `validate_promo_code` action requires CSRF tokens
- No `skip_before_action :verify_authenticity_token` (CSRF protection is enabled)

**Frontend:** `app/javascript/modules/promo_code_handler.js`
```javascript
validateOrderPromoCode(promoField, resultDiv) {
  const code = promoField.value.trim();

  fetch('/orders/validate_promo_code', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': this.getCSRFToken()  // ✓ CSRF token included
    },
    body: JSON.stringify({ promo_code: code })
  })
  .then(response => response.json())
  .then(data => { /* handle response */ })
}
```

## When CSRF Protection is NOT Required

CSRF protection is only needed for **state-changing** operations (POST/PUT/PATCH/DELETE). The following do NOT require CSRF tokens:

### GET Requests

```javascript
// No CSRF token needed for GET requests
fetch('/api/data', {
  method: 'GET',
  headers: {
    'Content-Type': 'application/json'
    // No X-CSRF-Token required
  }
})
```

### External Webhooks

External services (Stripe, Twilio, etc.) cannot include CSRF tokens. These use alternative authentication:

- **Stripe:** Signature verification via `Stripe::Webhook.construct_event`
- **Twilio:** Request validation via `Twilio::Security::RequestValidator`

**Example:** `app/controllers/stripe_webhooks_controller.rb` has `skip_before_action :verify_authenticity_token` with security justification.

### API Endpoints with API Key Authentication

Stateless API endpoints using API key authentication don't use session-based CSRF:

**Example:** `app/controllers/api/v1/businesses_controller.rb` uses API key instead of CSRF tokens.

### OAuth Callbacks

OAuth 2.0 flows use the `state` parameter for CSRF protection instead of Rails CSRF tokens:

**Example:** `app/controllers/calendar_oauth_controller.rb` validates OAuth state parameter.

## Adding New AJAX Endpoints

When creating a new AJAX endpoint, follow this checklist:

### Backend (Controller)

1. **DO NOT** add `skip_before_action :verify_authenticity_token` unless absolutely necessary
2. If skipping is required, add comprehensive documentation:
   ```ruby
   # SECURITY: CSRF skip is LEGITIMATE because [reason]
   # - [Explanation of why skip is safe]
   # - [Alternative security measures in place]
   # - Related security: CWE-352 (CSRF) mitigation via [method]
   skip_before_action :verify_authenticity_token, only: [:action_name], if: :json_request?
   ```
3. Ensure the endpoint only responds to JSON requests if skipping CSRF

### Frontend (JavaScript)

1. **ALWAYS** include the CSRF token in non-GET requests:
   ```javascript
   headers: {
     'X-CSRF-Token': this.getCSRFToken()
   }
   ```
2. Test in development to ensure 422 errors don't occur
3. Handle errors gracefully if CSRF token is missing/invalid

## Testing CSRF Protection

### Manual Testing in Browser Console

Test that CSRF protection works by trying to make a request WITHOUT the token:

```javascript
// This SHOULD fail with 422 Unprocessable Entity
fetch('/orders/validate_promo_code', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  // Intentionally omitting X-CSRF-Token
  body: JSON.stringify({ promo_code: 'TEST' })
})
```

### Automated Testing

See `spec/requests/csrf_protection_spec.rb` for comprehensive CSRF configuration tests.

## Common Issues and Solutions

### Issue: 422 Unprocessable Entity on AJAX Requests

**Symptoms:** AJAX POST requests fail with 422 status code

**Cause:** CSRF token not included in request headers

**Solution:** Add `'X-CSRF-Token': this.getCSRFToken()` to request headers

### Issue: Invalid CSRF Token After Session Expiry

**Symptoms:** Users get CSRF errors after being idle for a long time

**Cause:** Session expired, CSRF token no longer valid

**Solution:**
- Frontend: Detect 422 errors and prompt user to refresh page
- Backend: Use `rescue_from ActionController::InvalidAuthenticityToken` (see admin/sessions_controller.rb)

### Issue: CSRF Token Missing from Page

**Symptoms:** `getCSRFToken()` returns empty string

**Cause:** Meta tag not rendered in layout

**Solution:** Ensure `<%= csrf_meta_tags %>` is in application layout

## Security Best Practices

1. ✅ **Always include CSRF tokens** in POST/PUT/PATCH/DELETE requests
2. ✅ **Never disable CSRF** unless you have alternative security measures
3. ✅ **Document all CSRF skips** with CWE-352 references and justifications
4. ✅ **Test CSRF protection** in development and staging before deploying
5. ✅ **Use HTTPS** to prevent CSRF token interception
6. ✅ **Keep sessions secure** with `httponly` and `secure` flags on cookies

## Related Documentation

- [CSRF Protection Configuration](./csrf_protection_spec.rb)
- [Admin Sessions CSRF Handling](../app/controllers/admin/sessions_controller.rb)
- [Rails Security Guide](https://guides.rubyonrails.org/security.html#cross-site-request-forgery-csrf)
- [CWE-352: Cross-Site Request Forgery](https://cwe.mitre.org/data/definitions/352.html)

## Changelog

- **2025-10-25:** Initial documentation created
- **2025-10-25:** Removed CSRF skip from Public::OrdersController#validate_promo_code (now requires CSRF tokens)
