# Be sure to restart your server when you modify this file.

# Configure session store based on environment
if Rails.env.production?
  # Use cookie store with secure options for production
  Rails.application.config.session_store :cookie_store, 
                                         key: '_bizblasts_session', 
                                         domain: 'bizblasts.com', # TLD for production
                                         secure: true, 
                                         httponly: true
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