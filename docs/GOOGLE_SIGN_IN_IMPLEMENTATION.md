# Google Sign-In Implementation Plan

## Overview

This document outlines the implementation of Google Sign-In (OAuth 2.0) for BizBlasts, supporting both sign-in and sign-up flows across all domains (main domain, tenant subdomains, and custom domains).

## Requirements

1. **User Scope**: All user types (clients, managers, staff)
2. **Account Linking**: Automatically link Google accounts to existing accounts with matching email
3. **Registration Flow**: Google sign-up available on each registration page (client, business) alongside email registration
4. **Domain Strategy**: Works on all domains (main, subdomains, custom domains)
5. **Email Confirmation**: Existing confirmation flow unchanged (Google users still need email confirmation)

## Implementation Status

- [x] **Phase 1: Dependencies & Database** ✅
  - [x] Add `omniauth-google-oauth2` gem
  - [x] Add `omniauth-rails_csrf_protection` gem
  - [x] Create migration for `provider` and `uid` columns on users table
  - [x] Run migration

- [x] **Phase 2: Configuration** ✅
  - [x] Configure Devise with OmniAuth Google
  - [x] Add environment variables for Google OAuth credentials
  - [x] Document required variables

- [x] **Phase 3: User Model** ✅
  - [x] Add `:omniauthable` to User model
  - [x] Implement `from_omniauth` class method
  - [x] Handle automatic account linking
  - [x] Add `oauth_user?` helper method
  - [x] Update `password_required?` for OAuth users

- [x] **Phase 4: Controllers** ✅
  - [x] Create `Users::OmniauthCallbacksController`
  - [x] Handle sign-in flow
  - [x] Handle sign-up flow (client vs business)
  - [x] Handle cross-domain authentication via auth bridge

- [x] **Phase 5: Routes** ✅
  - [x] Add OmniAuth callback routes
  - [x] Add OAuth setup route for pre-OAuth session storage
  - [x] Configure for multi-domain support

- [x] **Phase 6: Views** ✅
  - [x] Add Google sign-in button to sign-in page
  - [x] Add Google sign-up button to client registration page
  - [x] Add Google sign-up button to business registration page
  - [x] Style buttons consistently with existing UI
  - [x] Handle OAuth pre-fill for business registration (shows/hides password fields)
  - [x] Update controllers to handle OAuth data in session

- [x] **Phase 7: Cross-Domain Support** ✅
  - [x] Handle OAuth callback on main domain
  - [x] Store origin host and business ID in session before OAuth
  - [x] Bridge authentication to tenant domains via AuthToken
  - [x] Validate return URLs for security (prevent open redirects)

- [x] **Phase 8: Testing** ✅
  - [x] Add OmniAuth test helpers (`spec/support/omniauth_helpers.rb`)
  - [x] Add model specs for `from_omniauth` and `oauth_user?`
  - [x] Add model specs for `password_required?` with OAuth users
  - [x] Add controller specs for OmniAuth callbacks
  - [x] Add request specs for OAuth setup

## Technical Details

### Database Schema Changes

```ruby
# Migration: add_omniauth_to_users
add_column :users, :provider, :string
add_column :users, :uid, :string
add_index :users, [:provider, :uid], unique: true
```

### Environment Variables

**Uses the same credentials as Google Calendar integration:**

```bash
# Production
GOOGLE_OAUTH_CLIENT_ID=your_google_client_id
GOOGLE_OAUTH_CLIENT_SECRET=your_google_client_secret

# Development/Test
GOOGLE_OAUTH_CLIENT_ID_DEV=your_dev_google_client_id
GOOGLE_OAUTH_CLIENT_SECRET_DEV=your_dev_google_client_secret
```

### OAuth Callback URL Configuration

**Add these callback URLs to your existing Google OAuth client's authorized redirect URIs:**

- Production: `https://www.bizblasts.com/users/auth/google_oauth2/callback`
- Development: `http://lvh.me:3000/users/auth/google_oauth2/callback`

> **Note:** These are added to the same OAuth client used for Google Calendar integration. No separate credentials needed.

After successful authentication, users are redirected back to their original domain via the auth bridge.

### User Flow

1. User clicks "Sign in with Google" or "Sign up with Google"
2. User is redirected to Google's OAuth consent screen
3. User authorizes BizBlasts
4. Google redirects to callback URL on main domain
5. System checks if user exists:
   - **Existing user with matching email**: Link Google account, sign in
   - **Existing user with provider/uid**: Sign in directly
   - **New user**: Create account based on registration context (client/business)
6. If on tenant domain, create auth bridge token and redirect back

## Security Considerations

1. **State Parameter**: OmniAuth uses state parameter for CSRF protection
2. **Email Verification**: Google-verified emails are trusted but confirmation flow unchanged
3. **Account Linking**: Only automatic for exact email matches
4. **Cross-Domain**: Uses existing secure auth bridge system

## Dependencies

- `omniauth-google-oauth2` (~> 1.1)
- `omniauth-rails_csrf_protection` (~> 1.0)

## Files Created/Modified

### New Files
- `app/controllers/users/omniauth_callbacks_controller.rb` - Handles OAuth callbacks
- `app/controllers/users/omniauth_setup_controller.rb` - Pre-OAuth session setup
- `spec/support/omniauth_helpers.rb` - Test helpers for OmniAuth
- `spec/controllers/users/omniauth_callbacks_controller_spec.rb` - Controller tests
- `spec/requests/users/omniauth_setup_spec.rb` - Request specs

### Modified Files
- `Gemfile` - Added omniauth gems
- `config/initializers/devise.rb` - OmniAuth configuration
- `config/routes.rb` - OAuth routes
- `app/models/user.rb` - Omniauthable module and from_omniauth method
- `app/views/devise/sessions/new.html.erb` - Google sign-in button
- `app/views/client/registrations/new.html.erb` - Google sign-up button
- `app/views/business/registrations/new.html.erb` - Google sign-up button
- `app/controllers/client/registrations_controller.rb` - OAuth data handling
- `app/controllers/business/registrations_controller.rb` - OAuth data handling
- `spec/models/user_spec.rb` - OAuth-related tests
- `db/migrate/20251223202350_add_omniauth_to_users.rb` - Migration

---

*Last Updated: December 23, 2024*
*Status: ✅ COMPLETE*

