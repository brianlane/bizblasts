# Be sure to restart your server when you modify this file.

# Configure session store based on environment
# In production we need to support two scenarios:
# 1. Main platform domain and its sub-domains (e.g. bizblasts.com, tenant.bizblasts.com)
# 2. Independent custom domains that belong to tenants (e.g. newcoworker.com)
#
# Using a static cookie `domain` breaks CSRF/session handling on the custom domain flow
# because browsers refuse to store a cookie for a different domain. Instead we
# compute the cookie domain per-request:
#   • If the host ends with our platform domain we return ".bizblasts.com" so the
#     session is shared across all sub-domains.
#   • Otherwise we return the exact host so the session is scoped to the custom
#     domain only (no wildcard) – this avoids leaking cookies between tenants.
#
# Rails 7+ supports a lambda for the `domain:` option.

if Rails.env.production?
  Rails.application.config.session_store :cookie_store,
                                         key: '_bizblasts_session',
                                         domain: ->(request) do
                                           host = request.host
                                           platform_domain = 'bizblasts.com'

                                           if host.ends_with?(platform_domain)
                                             ".#{platform_domain}"
                                           else
                                             host # Custom domain – isolate cookie
                                           end
                                         end,
                                         secure: true,
                                         httponly: true,
                                         same_site: :lax
elsif Rails.env.development?
  # For development with lvh.me, allow all subdomains
  Rails.application.config.session_store :cookie_store, 
                                         key: '_bizblasts_session',
                                         domain: :all, # Use :all for lvh.me subdomains
                                         tld_length: 2 # Important for lvh.me
else
  # For test environment, allow all subdomains as well
  Rails.application.config.session_store :cookie_store, 
                                         key: '_bizblasts_session_test', # Use a different key for test to avoid clashes
                                         domain: :all,
                                         tld_length: 2 # Important for lvh.me
end