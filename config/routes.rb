# frozen_string_literal: true

require Rails.root.join('lib/constraints/subdomain_constraint')
require Rails.root.join('lib/constraints/custom_domain_constraint')
require Rails.root.join('lib/constraints/business_domain_constraint')
require Rails.root.join('lib/constraints/tenant_public_constraint')

Rails.application.routes.draw do
  # Health check routes - MUST be first to avoid being caught by catch-all routes
  get "up" => "rails/health#show", as: :rails_health_check
  get "healthcheck" => "health#check", as: :health_check
  get "db-check" => "health#db_check", as: :db_check
  get "maintenance" => "maintenance#index", as: :maintenance
  
  # Authentication bridge routes for cross-domain authentication
  # These must be accessible globally (not constrained to tenants)
  get "auth/bridge" => "authentication_bridge#create", as: :auth_bridge
  post "auth/bridge/consume" => "authentication_bridge#consume", as: :auth_bridge_consume
  get "auth/bridge/health" => "authentication_bridge#health", as: :auth_bridge_health
  
  # Token consumption endpoint for custom domains
  # This endpoint receives the redirect from the main domain auth bridge
  get "auth/consume" => "authentication_bridge#consume_token", as: :auth_consume

  # Reverse bridge: custom domain → main domain
  # This allows users to navigate back to main domain while staying logged in
  get "auth/bridge_to_main" => "authentication_bridge#bridge_to_main", as: :auth_bridge_to_main

  # Tenant public routes: available on both subdomains and active custom domains
  constraints TenantPublicConstraint do
    # (public routes continue)
    scope module: 'public' do
      get '/', to: 'pages#show', constraints: { page: /home|root|^$/ }, as: :tenant_root
      get '/about', to: 'pages#show', page: 'about', as: :tenant_about_page
      get '/services', to: 'pages#show', page: 'services', as: :tenant_services_page
      get '/services/:id', to: 'services#show', as: :tenant_service
      # Product listings under tenant public scope
      resources :products, only: [:index, :show]
      
      # Rental listings and bookings
      resources :rentals, only: [:index, :show] do
        member do
          get :availability
          get :calendar
          get :available_slots
          get :book
          post :create_booking
        end
      end
      resources :rental_bookings, only: [:show] do
        member do
          get :pay_deposit
          post :submit_deposit
          get :deposit_success
          get :deposit_cancel
          get :confirmation
        end
      end
      
      get '/contact', to: 'pages#show', page: 'contact', as: :tenant_contact_page

      # Estimate page and form submission
      get '/estimate', to: 'pages#show', page: 'estimate', as: :tenant_estimate_page
      post '/estimate', to: 'requests#create', as: :tenant_estimate_request

      get '/calendar', to: 'tenant_calendar#index', as: :tenant_calendar
      get '/available-slots', to: 'tenant_calendar#available_slots', as: :tenant_available_slots
      get '/staff-availability', to: 'tenant_calendar#staff_availability', as: :tenant_staff_availability

      get '/book', to: 'booking#new', as: :new_tenant_booking
      resources :booking, only: [:create], as: :tenant_bookings
      get '/booking/:id/confirmation', to: 'booking#confirmation', as: :tenant_booking_confirmation

      get '/my-bookings', to: 'client_bookings#index', as: :tenant_my_bookings
      get '/my-bookings/:id', to: 'client_bookings#show', as: :tenant_my_booking, constraints: { id: /\d+/ }
      # Add alias for backward compatibility with tests
      get '/booking/:id', to: 'client_bookings#show', as: :tenant_booking, constraints: { id: /\d+/ }
      patch '/my-bookings/:id/cancel', to: 'client_bookings#cancel', as: :cancel_tenant_my_booking, constraints: { id: /\d+/ }

      resources :invoices, only: [:index, :show], as: :tenant_invoices do
        post :pay, on: :member
      end
      resources :payments, only: [:index, :new, :create]
      
      # Tips for experience bookings
      resources :bookings, only: [] do
        resources :tips, only: [:new, :create] do
          member do
            get :success
            get :cancel
          end
        end
      end
      
      # Unified transactions view
      resources :transactions, only: [:index, :show]

      # Public checkout/cart/orders/subscriptions/policies are defined below with tenant_* helpers

      # Business-specific loyalty (on subdomain)
      get '/loyalty', to: 'loyalty#show', as: :tenant_loyalty
      post '/loyalty/redeem', to: 'loyalty#redeem_points', as: :tenant_loyalty_redeem

      # Direct referral program access for current tenant
      get '/referral', to: 'referral#show', as: :tenant_referral_program

      # Public cart/checkout and subscriptions - MUST come before catch-all
      resource  :cart, only: [:show]
      resources :line_items, only: [:create, :update, :destroy]
      resources :orders,     only: [:new, :create, :index, :show] do
        collection { post :validate_promo_code }
      end
      resources :subscriptions, only: [:new, :create] do
        member { get :confirmation }
      end
      resources :newsletter_subscriptions, only: [:create]
      resource :service_area_check, only: [:new, :create]
      resources :policy_acceptances, only: [:create, :show]
      get '/policy_status', to: 'policy_acceptances#status'
      post '/policy_acceptances/bulk', to: 'policy_acceptances#bulk_create'

      # Tip collection routes (token-based for experiences)
      resources :tips, only: [:new, :create, :show] do
        member do
          get :success
          get :cancel
        end
      end

      # Catch-all for static pages must come last
      get '/:page', to: 'pages#show', as: :tenant_page
    end
  end

  # API routes for AI/LLM discovery
  namespace :api do
    namespace :v1 do
      resources :businesses, only: [:index, :show] do
        collection do
          get :categories
          get :ai_summary
        end
      end
    end
  end
  
  # Theme test routes for development and previewing
  get '/theme-test', to: 'theme_test#index', as: :theme_test
  get '/theme-test/preview/:theme_id', to: 'theme_test#preview', as: :theme_test_preview
  get '/theme-test/business/:business_subdomain', to: 'theme_test#preview', as: :theme_test_business
  
  # Stripe app deep link test (for development/testing)
  get '/stripe-app-test', to: 'stripe_app_test#show', as: :stripe_app_test
  
  post '/webhooks/stripe', to: 'stripe_webhooks#create'
  post '/webhooks/twilio', to: 'webhooks/twilio#delivery_receipt'
  post '/webhooks/twilio/inbound', to: 'webhooks/twilio#inbound_message'

  # Email Marketing webhooks
  get '/webhooks/email-marketing/mailchimp', to: 'webhooks/email_marketing#mailchimp_verify'
  post '/webhooks/email-marketing/mailchimp', to: 'webhooks/email_marketing#mailchimp'
  post '/webhooks/email-marketing/constant-contact', to: 'webhooks/email_marketing#constant_contact'
  
  # SMS link redirects
  get '/s/:short_code', to: 'sms_links#redirect', as: :sms_link_redirect
  
  # Calendar OAuth callback (outside subdomain constraint for security)
  get '/oauth/calendar/:provider/callback', to: 'calendar_oauth#callback', as: :calendar_oauth_callback

  # Google Business Profile OAuth callback (outside subdomain constraint)
  get '/oauth/google-business/callback', to: 'google_business_oauth#callback', as: :google_business_oauth_callback

  # Video Meeting OAuth callbacks (outside subdomain constraint for security)
  get '/oauth/video/zoom/callback', to: 'video_meeting_oauth#callback', defaults: { provider: 'zoom' }, as: :zoom_video_oauth_callback
  get '/oauth/video/google-meet/callback', to: 'video_meeting_oauth#callback', defaults: { provider: 'google_meet' }, as: :google_meet_video_oauth_callback

  # QuickBooks OAuth callback (outside subdomain constraint for security)
  get '/oauth/quickbooks/callback', to: 'quickbooks_oauth#callback', as: :quickbooks_oauth_callback

  # Email Marketing OAuth callbacks (Mailchimp, Constant Contact)
  get '/oauth/email-marketing/:provider/callback', to: 'email_marketing_oauth#callback', as: :email_marketing_oauth_callback
  # Add routes for admin bookings availability before ActiveAdmin is initialized
  get '/admin/bookings-availability/slots', to: 'admin/booking_availability#available_slots', as: :available_slots_bookings
  get '/admin/bookings-availability/new', to: 'admin/booking_availability#new', as: :new_admin_booking_from_slots
  
  # Debug route to test available slots
  get '/debug/available-slots', to: 'admin/booking_availability#available_slots'
  
  # ActiveAdmin routes
  devise_for :admin_users, ActiveAdmin::Devise.config.merge(controllers: {
    sessions: 'admin/sessions'
  })
  ActiveAdmin.routes(self)

  # Custom routes for SolidQueue job actions (Rails 8.1 compatible - avoids page_action deprecation)
  namespace :admin do
    post 'solid_queue_jobs/retry_all_failed_jobs', to: 'solid_queue_jobs#retry_all_failed_jobs', as: :solid_queue_jobs_retry_all_failed_jobs
    post 'solid_queue_jobs/retry_failed_job', to: 'solid_queue_jobs#retry_failed_job', as: :solid_queue_jobs_retry_failed_job
    post 'solid_queue_jobs/cleanup_orphaned_jobs', to: 'solid_queue_jobs#cleanup_orphaned_jobs', as: :solid_queue_jobs_cleanup_orphaned_jobs
    post 'solid_queue_jobs/remove_all_failed_jobs', to: 'solid_queue_jobs#remove_all_failed_jobs', as: :solid_queue_jobs_remove_all_failed_jobs
    post 'solid_queue_jobs/discard_day_old_jobs', to: 'solid_queue_jobs#discard_day_old_jobs', as: :solid_queue_jobs_discard_day_old_jobs
  end
  
  devise_for :users, skip: [:registrations], controllers: {
    sessions: 'users/sessions',
    magic_links: 'users/magic_links'
  }

  namespace :passwordless do
    devise_for :users, skip: [:registrations], controllers: {
      sessions: 'devise/passwordless/sessions'
    }
  end

  devise_for :businesses, skip: [:registrations], controllers: {
    sessions: 'businesses/sessions',
  }

  # Redirect old signup URL to new business signup URL
  get '/users/sign_up', to: redirect('/business/sign_up')

  # Protocol and subdomain redirects for SEO indexing
  # These handle the URLs that Google Search Console is finding as "pages with redirects"
  constraints(host: /^bizblasts\.com$/) do
    # Redirect non-www to www version
    get '(*path)', to: redirect { |params, request|
      protocol = request.ssl? ? 'https://' : 'http://'
      # In production, force HTTPS and www
      if Rails.env.production?
        "https://www.bizblasts.com/#{params[:path]}"
      else
        "#{protocol}www.bizblasts.com/#{params[:path]}"
      end
    }
  end

  devise_scope :user do
    get '/client/sign_up', to: 'client/registrations#new', as: :new_client_registration
    post '/client', to: 'client/registrations#create', as: :client_registration

    get '/business/sign_up', to: 'business/registrations#new', as: :new_business_registration
    post '/business', to: 'business/registrations#create', as: :business_registration

    get '/users/edit', to: 'users/registrations#edit', as: :edit_user_registration
    patch '/users', to: 'users/registrations#update', as: :user_registration
    put '/users', to: 'users/registrations#update'
    delete '/users', to: 'users/registrations#destroy'

    get '/users/sign_out', to: 'users/sessions#destroy'
  end

  # Business Manager routes available on both subdomains and custom domains
  constraints BusinessDomainConstraint do
    namespace :business_manager, path: '/manage' do
      get '/dashboard', to: 'dashboard#index', as: :dashboard
      resources :services do
        member do
          patch :update_position
          patch :move_up
          patch :move_down
          get 'manage_availability'
          patch 'manage_availability'
          patch :clear_availability
        end
        resources :service_variants, except: [:show]
      end
      resources :products do
        member do
          patch :update_position
          patch :move_up
          patch :move_down
        end
      end
      
      # Rental product management
      resources :rentals do
        member do
          patch :update_position
          get :availability
          get :manage_availability
          patch :update_availability
        end
      end
      
      # Rental bookings management
      resources :rental_bookings do
        member do
          patch :check_out
          patch :process_return
          patch :complete
          patch :cancel
        end
        collection do
          get :calendar
          get :overdue
        end
      end
      resources :shipping_methods
      resources :tax_rates
      resources :customers
      resources :staff_members do
        member do
          get 'manage_availability'
          patch 'manage_availability'
        end
      end

      # Gallery management
      get 'gallery', to: 'gallery#index', as: :gallery_index
      scope path: 'gallery', as: :gallery, controller: 'gallery' do
        post 'photos', action: :create_photo, as: :photos
        post 'photos/reorder', action: :reorder_photos, as: :reorder_photos
        patch 'photos/:id', action: :update_photo, as: :update_photo
        delete 'photos/:id', action: :destroy_photo, as: :destroy_photo
        post 'video', action: :create_video, as: :video
        patch 'video', action: :update_video, as: :update_video
        delete 'video', action: :destroy_video, as: :destroy_video
      end

      # Bookings management
      resources :bookings, only: [:index, :show, :new, :edit, :update, :create] do
        member do
          patch 'confirm'
          patch 'cancel'
          patch 'refund'
          get 'reschedule'
          patch 'update_schedule'
        end
        collection do
          get '/available-slots', to: 'bookings#available_slots', as: :available_slots
        end
      end

      # Add route for available slots in business manager context
      get '/available-slots', to: 'bookings#available_slots', as: :available_slots_bookings

      # Allow staff/manager to create bookings
      resources :client_bookings, only: [:new, :create], path: 'my-bookings'
      # Estimates management
      resources :estimates do
        member do
          patch :send_to_customer
          patch :resend_to_customer
          get :download_pdf
          post :duplicate
          get :versions
          patch 'restore_version/:version_id', action: :restore_version, as: :restore_version
        end
      end

      # Business transactions management (unified orders and invoices)
      resources :transactions, only: [:index, :show] do
        collection do
          get :download_csv
        end
      end

      # CSV Import/Export
      resources :csv, only: [:index] do
        collection do
          get 'export/:type', action: :export, as: :export
          get 'template/:type', action: :template, as: :template
          get 'import/:type', action: :import_form, as: :import_form
          post 'import/:type', action: :import, as: :import
          get 'import/:id/status', action: :import_status, as: :import_status
          get 'import/:id/errors', action: :import_errors, as: :import_errors
        end
      end

      resources :document_templates do
        member do
          get :send_document
          post :create_and_send
        end
      end

      # Business orders management
      resources :orders, only: [:index, :show, :new, :create, :edit, :update] do
        member do
          patch :refund
        end
      end
      resources :invoices, only: [:index, :show] do
        post :resend, on: :member
        patch :cancel, on: :member
        patch :mark_as_paid, on: :member
        get :qr_payment, on: :member
        get :payment_status, on: :member
      end

      # Business payments management
      resources :payments, only: [:index, :show]

      # Payment collection (singular resource for new payment collection)
      resource :payment, only: [:new, :create]

      # Redirect /manage/payment to /manage/payment/new to prevent 404s
      get '/payment', to: redirect('/manage/payment/new')
      get '/settings', to: 'settings#index', as: :settings

      # Route to dismiss individual business setup reminder tasks for the current user
      delete 'setup_reminder', to: 'base#dismiss_setup_reminder', as: :setup_reminder

      namespace :settings do
        resource :profile, only: [:edit, :update, :destroy] do
          patch :unsubscribe_all, on: :member
        end
        resource :business, only: [:edit, :update], controller: 'business' do
          post :connect_stripe
          get :stripe_onboarding
          post :refresh_stripe
          delete :disconnect_stripe
          post :check_subdomain_availability
          get  :check_subdomain_availability
          get  :check_domain_status
          post :finalize_domain_activation
        end
        resources :teams, only: [:index, :new, :create, :destroy]
        resource :booking_policy, only: [:show, :edit, :update]
        resources :locations

        # Integrations (Module 9)
        resources :integrations, only: [:index] do
          collection do
            # Google Business connection routes
            get 'google-business/search', action: :google_business_search
            get 'google-business/search-nearby', action: :google_business_search_nearby
            get 'google-business/details/:place_id', action: :google_business_details, as: :google_business_details
            post 'google-business/connect', action: :google_business_connect
            post 'google-business/connect-manual', action: :google_business_connect_manual
            delete 'google-business/disconnect', action: :google_business_disconnect
            get 'google-business/status', action: :google_business_status
            post 'lookup-place-id', action: :lookup_place_id
            get 'check-place-id-status/:job_id', action: :check_place_id_status

            # Google Business Profile OAuth routes
            get 'google-business/oauth/authorize', action: :google_business_oauth_authorize

            # Calendar integration routes
            post 'calendar-integrations/connect', action: :calendar_integration_connect, as: :calendar_integration_connect
            get 'calendar-integrations/new-caldav', action: :calendar_integration_new_caldav, as: :calendar_integration_new_caldav
            post 'calendar-integrations/create-caldav', action: :calendar_integration_create_caldav, as: :calendar_integration_create_caldav
            post 'calendar-integrations/test-caldav', action: :calendar_integration_test_caldav, as: :calendar_integration_test_caldav
            post 'calendar-integrations/batch-sync', action: :calendar_integration_batch_sync, as: :calendar_integration_batch_sync
            post 'calendar-integrations/import-availability', action: :calendar_integration_import_availability, as: :calendar_integration_import_availability
            get 'calendar-integrations/:calendar_integration_id', action: :calendar_integration_show, as: :calendar_integration_show
            delete 'calendar-integrations/:calendar_integration_id', action: :calendar_integration_destroy, as: :calendar_integration_destroy
            patch 'calendar-integrations/:calendar_integration_id/toggle-default', action: :calendar_integration_toggle_default, as: :calendar_integration_toggle_default
            post 'calendar-integrations/:calendar_integration_id/resync', action: :calendar_integration_resync, as: :calendar_integration_resync

            # Video meeting integration routes
            post 'video-integrations/connect', action: :video_integration_connect, as: :video_integration_connect
            post 'video-integrations/link-from-calendar', action: :video_integration_link_from_calendar, as: :video_integration_link_from_calendar
            delete 'video-integrations/:id', action: :video_integration_destroy, as: :video_integration_destroy
            get 'video-integrations/:id/status', action: :video_integration_status, as: :video_integration_status

            # ADP Payroll export routes
            patch 'adp-payroll/config', action: :adp_payroll_config_update, as: :adp_payroll_config_update
            post 'adp-payroll/exports', action: :adp_payroll_export_create, as: :adp_payroll_export_create
            get 'adp-payroll/exports/:id/download', action: :adp_payroll_export_download, as: :adp_payroll_export_download

            # QuickBooks Online routes
            get 'quickbooks/oauth/authorize', action: :quickbooks_oauth_authorize, as: :quickbooks_oauth_authorize
            delete 'quickbooks/disconnect', action: :quickbooks_disconnect, as: :quickbooks_disconnect
            post 'quickbooks/exports/invoices', action: :quickbooks_export_invoices, as: :quickbooks_export_invoices
            patch 'quickbooks/config', action: :quickbooks_config_update, as: :quickbooks_config_update
            post 'quickbooks/exports/:id/retry', action: :quickbooks_export_retry_failed, as: :quickbooks_export_retry_failed

            # Email Marketing integration routes (Mailchimp, Constant Contact)
            get 'mailchimp/oauth/authorize', action: :mailchimp_oauth_authorize, as: :mailchimp_oauth_authorize
            delete 'mailchimp/disconnect', action: :mailchimp_disconnect, as: :mailchimp_disconnect
            get 'constant-contact/oauth/authorize', action: :constant_contact_oauth_authorize, as: :constant_contact_oauth_authorize
            delete 'constant-contact/disconnect', action: :constant_contact_disconnect, as: :constant_contact_disconnect
            get 'email-marketing/:provider/lists', action: :email_marketing_lists, as: :email_marketing_lists
            patch 'email-marketing/:provider/config', action: :email_marketing_update_config, as: :email_marketing_update_config
            post 'email-marketing/:provider/sync', action: :email_marketing_sync, as: :email_marketing_sync
            get 'email-marketing/:provider/sync-status', action: :email_marketing_sync_status, as: :email_marketing_sync_status
          end
        end
        resource :website_pages, only: [:edit, :update]

        # Tips configuration
        resource :tips, only: [:show, :update]

        resource :sidebar, only: [:show], controller: 'sidebar' do
          get :edit_sidebar
          patch :update_sidebar
        end
      end

      # Customer Subscription Management for Business Managers
      resources :customer_subscriptions, path: 'subscriptions' do
        member do
          patch :cancel
          get :billing_history
        end
        collection do
          get :analytics
        end
      end

      # Referral and Loyalty Management
      resources :referrals, only: [:index, :show, :edit, :update, :create] do
        collection do
          patch :toggle_status
          get :analytics
        end
      end

      resources :loyalty, only: [:index, :show, :edit, :update, :create] do
        collection do
          patch :toggle_status
          get :customers
          get :analytics
        end
        member do
          get :customer_detail
          post :adjust_points
        end
      end

      # Platform (BizBlasts) Loyalty and Referrals
      resources :platform, only: [:index] do
        collection do
          post :generate_referral_code
          post :redeem_points
          get :transactions
          get :referrals
          get :discount_codes
        end
      end

      # Promotion Management
      resources :promotions do
        collection do
          patch :bulk_deactivate
        end
        member do
          patch :toggle_status
        end
      end

      # Subscription management
      resources :customer_subscriptions, only: [:index, :show, :edit, :update, :destroy] do
        member do
          patch :cancel
        end
      end

      # Subscription loyalty management
      resources :subscription_loyalty, only: [:index, :show] do
        member do
          post :award_points
          patch :adjust_tier
        end
        collection do
          get :customers
          get :analytics
          get :export_data
        end
      end

      # Website customization routes (Standard & Premium only)
      namespace :website do
        resources :pages do
          collection do
            patch :update_priority
          end
          member do
            get :preview
            patch :publish
            post :create_version
            patch :restore_version
            post :duplicate
            post :track_view
          end

          resources :sections, except: [:show] do
            member do
              patch :move_up
              patch :move_down
              post :duplicate
              patch :reorder
            end

            collection do
              patch :reorder
            end
          end
        end

        resources :themes do
          member do
            patch :activate
            get :preview
            post :duplicate
            get :export
          end

          collection do
            post :import
          end
        end

        resources :templates, only: [:index, :show] do
          member do
            post :apply
            get :preview
          end

          collection do
            get :search
            get :filter_by_industry
            get :compare
          end
        end
      end
    end
  end

  # Subdomain-only routes (business routes, policy redirects, etc.)
  constraints(SubdomainConstraint) do
    # Business-specific routes for business owners
    namespace :business do
      resources :orders, only: [:index, :show]
    end

    # Public cart/checkout and subscriptions now handled by TenantPublicConstraint (see top block)

    # Policy pages for subdomain users (redirect to main domain)
    get '/privacypolicy', to: redirect { |params, request| 
      protocol = request.protocol
      port = request.port != 80 ? ":#{request.port}" : ""
      "#{protocol}#{request.domain}#{port}/privacypolicy"
    }
    get '/terms', to: redirect { |params, request| 
      protocol = request.protocol
      port = request.port != 80 ? ":#{request.port}" : ""
      "#{protocol}#{request.domain}#{port}/terms"
    }
    get '/acceptableusepolicy', to: redirect { |params, request| 
      protocol = request.protocol
      port = request.port != 80 ? ":#{request.port}" : ""
      "#{protocol}#{request.domain}#{port}/acceptableusepolicy"
    }
    get '/returnpolicy', to: redirect { |params, request| 
      protocol = request.protocol
      port = request.port != 80 ? ":#{request.port}" : ""
      "#{protocol}#{request.domain}#{port}/returnpolicy"
    }

    # Add a redirect for /settings under subdomain to the main domain
    get '/settings', to: redirect { |params, request| 
      # Extract the protocol and port
      protocol = request.protocol
      port = request.port != 80 ? ":#{request.port}" : ""
      
      # Redirect to main domain's settings page
      "#{protocol}#{request.domain}#{port}/settings"
    }

    # Tenant public routes are unified by TenantPublicConstraint (see top block)
  end

  # Redirect management/dashboard for custom-domain hosts ONLY (after public routes)
  # This now serves as a fallback for unauthenticated users on custom domains
  # constraints CustomDomainConstraint do
  #   get '/manage(/*path)', to: 'tenant_redirect#manage', as: :tenant_manage_redirect
  # end

  # Fallback redirect for unauthenticated users on custom domains
  # Uses Warden (Devise) to reliably detect authentication state instead of relying on raw session keys.
  constraints lambda { |req|
    CustomDomainConstraint.matches?(req) && !(req.env["warden"]&.user.present?)
  } do
    get '/manage(/*path)', to: 'tenant_redirect#manage', as: :tenant_manage_redirect
  end


  # Fallback routes for base OrdersController new/create
  resources :orders, only: [:new, :create, :index, :show]

  resources :businesses, only: [:index]
  # Cart is now handled in TenantPublicConstraint block
  resources :line_items, only: [:create, :update, :destroy]
  # Add back the global products routes for controller specs
  resources :products, only: [:index, :show]
  root "home#index"

  # Route for checking business industry
  get '/check_business_industry', to: 'home#check_business_industry'

  # New static pages
  get '/about', to: 'home#about'
  get '/contact', to: 'home#contact'
  get '/cookies', to: 'home#cookies'
  get '/privacypolicy', to: 'home#privacy'
  get '/terms', to: 'home#terms'
  get '/disclaimer', to: 'home#disclaimer'
  get '/shippingpolicy', to: 'home#shippingpolicy'
  get '/returnpolicy', to: 'home#returnpolicy'
  get '/acceptableusepolicy', to: 'home#acceptableusepolicy'
  get '/pricing', to: 'home#pricing'
  
  # Documentation section
  get '/docs', to: 'docs#index'
  get '/docs/:doc_id', to: 'docs#show', as: :doc

  # Sitemap
  get '/sitemap.xml', to: 'sitemap#index', defaults: { format: 'xml' }
  
  # Web manifest for PWA support
  get '/site.webmanifest', to: proc { |env|
    file_path = Rails.root.join('public', 'site.webmanifest')
    if File.exist?(file_path)
      content = File.read(file_path)
      [200, {"Content-Type" => "application/manifest+json", "Cache-Control" => "public, max-age=86400"}, [content]]
    else
      [404, {"Content-Type" => "text/plain"}, ["Manifest not found"]]
    end
  }

  # Blog section
  get '/blog', to: 'blog#index', as: :blog
  get '/blog/feed.xml', to: 'blog#feed', as: :blog_feed, defaults: { format: 'xml' }
  get '/blog/:year/:month/:day/:slug', to: 'blog#show', as: :blog_post_by_date,
      constraints: { 
        year: /\d{4}/, 
        month: /\d{1,2}/, 
        day: /\d{1,2}/ 
      }
  get '/blog/:slug', to: 'blog#show', as: :blog_post

  # Route for contact form submission
  post '/contact', to: 'contacts#create'

  # Magic link-based unsubscribe route
  get '/unsubscribe/magic_link', to: 'public/unsubscribe#magic_link', as: :unsubscribe_magic_link
  
  # Review request unsubscribe route
  get '/unsubscribe/review_requests/:token', to: 'review_request_unsubscribes#show', as: :unsubscribe_review_requests

  # Policy acceptance routes
  resources :policy_acceptances, only: [:create, :show]
  get '/policy_status', to: 'policy_acceptances#status'
  post '/policy_acceptances/bulk', to: 'policy_acceptances#bulk_create'

  # Public subdomain availability endpoint
  get '/subdomains/check', to: 'public/subdomains#check', defaults: { format: :json }

  get "home/debug" => redirect("/admin/debug"), as: :old_tenant_debug
  get "admin/debug" => "admin/debug#index", as: :tenant_debug

  authenticated :user do
    root 'home#index', as: :authenticated_root
  end

  # Cross-business loyalty overview (main domain only)
  resources :loyalty, only: [:index], controller: 'public/loyalty'
  
  # Cross-business referral overview (main domain only)
  resources :referral, only: [:index], controller: 'public/referral'

  # Client dashboard and related routes (main domain only)
  get 'dashboard', to: 'client_dashboard#index'
  resources :client_bookings, path: 'my-bookings' do
    member do
      patch 'cancel'
    end
  end
  resources :client_rental_bookings, path: 'my-rentals', only: [:index, :show]

  # Client documents (waivers, agreements)
  namespace :client do
    resources :documents, path: 'my-documents', only: [:index, :show]
  end

  # New unified transactions view
  resources :transactions, only: [:index, :show]

  # Cart redirect handler for main domain
  # Since carts are business-specific, redirect users to the appropriate business domain
  resource :cart, only: [:show], controller: 'cart_redirect'

  authenticated :user, ->(user) { user.client? } do
    # Keep this block for any future client-specific routes that need the constraint
  end

  # Client Settings - moved outside authenticated block to allow proper redirects
  namespace :client, path: '' do # path: '' to avoid /client/client/settings
    resource :settings, only: [:show, :edit, :update, :destroy], controller: 'settings' do
      patch :unsubscribe_all, on: :member
    end
    
    # Client Subscription Management
    resources :subscriptions, only: [:index, :show, :edit, :update] do
      member do
        get :cancel
        post :cancel
        get :preferences
        patch :update_preferences
        get :billing_history
      end
    end
    
    # Subscription loyalty routes
    resources :subscription_loyalty, only: [:index, :show] do
      member do
        post :redeem_points
      end
      collection do
        get :tier_progress
        get :milestones
      end
    end
    
    resources :settings, only: [:index, :show, :edit, :update] do
      collection do
        get :subscriptions
        patch :update_subscriptions
      end
    end
  end

  # Client portal: estimates (My Estimates page)
  resources :estimates, only: [:index, :show], path: 'my-estimates', controller: 'client/estimates', as: :client_estimates

  # Public token-based estimate access (no authentication required)
  scope module: 'public' do
    get 'estimates/:token', to: 'estimates#show', as: :public_estimate
    patch 'estimates/:token/approve', to: 'estimates#approve', as: :approve_public_estimate
    patch 'estimates/:token/decline', to: 'estimates#decline', as: :decline_public_estimate
    post 'estimates/:token/request_changes', to: 'estimates#request_changes', as: :request_changes_public_estimate
    get 'estimates/:token/pdf', to: 'estimates#download_pdf', as: :download_public_estimate_pdf

    # Public token-based client document access (no authentication required)
    get 'documents/:token', to: 'client_documents#show', as: :public_client_document
    post 'documents/:token/sign', to: 'client_documents#sign', as: :sign_public_client_document
    get 'documents/:token/pdf', to: 'client_documents#download_pdf', as: :download_public_client_document_pdf
  end

  authenticated :user, ->(user) { user.admin? } do
    get 'dashboard', to: 'admin_dashboard#index'
  end

  # Fix for StaffController routes
  resources :staff, controller: 'staff' do
    member do
      get 'availability'
      patch 'update_availability'
    end
  end

  # Keep existing StaffMembersController routes
  resources :staff_members do
    member do
      get 'manage_availability'
      patch 'update_availability'
    end
  end

  get "/assets/:name-:digest.:format", to: proc { |env|
    name = env["action_dispatch.request.path_parameters"][:name]
    format = env["action_dispatch.request.path_parameters"][:format]
    
    digested_filename = "#{name}-#{env["action_dispatch.request.path_parameters"][:digest]}.#{format}"
    non_digested_filename = "#{name}.#{format}"
    
    possible_paths = [
      Rails.root.join('public', 'assets', digested_filename),
      Rails.root.join('public', 'assets', non_digested_filename),
      Rails.root.join('app', 'assets', 'builds', non_digested_filename)
    ]
    
    file_path = possible_paths.find { |path| File.exist?(path) }
    
    if file_path
      Rails.logger.info "Serving digested asset from: #{file_path}"
      content = File.read(file_path)
      content_type = case format
                     when 'css' then 'text/css'
                     when 'js' then 'application/javascript'
                     when 'png' then 'image/png'
                     when 'jpg', 'jpeg' then 'image/jpeg'
                     when 'gif' then 'image/gif'
                     when 'svg' then 'image/svg+xml'
                     else 'application/octet-stream'
                     end
      [200, {"Content-Type" => content_type, "Cache-Control" => "public, max-age=31536000"}, [content]]
    else
      Rails.logger.error "Digested asset not found: #{digested_filename} in paths: #{possible_paths.join(', ')}"
      [404, {"Content-Type" => "text/plain"}, ["Asset not found"]]
    end
  }

  get "/assets/:filename", to: proc { |env|
    filename = env["action_dispatch.request.path_parameters"][:filename]
    
    possible_paths = [
      Rails.root.join('public', 'assets', filename),
      Rails.root.join('app', 'assets', 'builds', filename)
    ]
    
    file_path = possible_paths.find { |path| File.exist?(path) }
    
    if file_path
      Rails.logger.info "Serving asset from: #{file_path}"
      content = File.read(file_path)
      content_type = case File.extname(filename)
                     when '.css' then 'text/css'
                     when '.js' then 'application/javascript'
                     when '.png' then 'image/png'
                     when '.jpg', '.jpeg' then 'image/jpeg'
                     when '.gif' then 'image/gif'
                     when '.svg' then 'image/svg+xml'
                     else 'application/octet-stream'
                     end
      [200, {"Content-Type" => content_type, "Cache-Control" => "public, max-age=31536000"}, [content]]
    else
      Rails.logger.error "Asset not found: #{filename} in paths: #{possible_paths.join(', ')}"
      [404, {"Content-Type" => "text/plain"}, ["Asset not found"]]
    end
  }

  get "/assets/active_admin.css", to: proc { |env|
    possible_paths = [
      Rails.root.join('public', 'assets', 'active_admin.css'),
      Rails.root.join('app', 'assets', 'builds', 'active_admin.css')
    ]
    
    file_path = possible_paths.find { |path| File.exist?(path) }
    
    if file_path
      Rails.logger.info "Serving ActiveAdmin CSS from: #{file_path}"
      content = File.read(file_path)
      [200, {"Content-Type" => "text/css", "Cache-Control" => "public, max-age=31536000"}, [content]]
    else
      Rails.logger.error "ActiveAdmin CSS not found in any of: #{possible_paths.join(', ')}"
      [404, {"Content-Type" => "text/plain"}, ["ActiveAdmin CSS not found"]]
    end
  }

  get "/assets/active_admin-:digest.css", to: proc { |env|
    file_path = Rails.root.join('public', 'assets', 'active_admin.css')
    
    if File.exist?(file_path)
      content = File.read(file_path)
      [200, {"Content-Type" => "text/css", "Cache-Control" => "public, max-age=31536000"}, [content]]
    else
      [404, {"Content-Type" => "text/plain"}, ["ActiveAdmin CSS not found"]]
    end
  }

  namespace :business_portal do
    # Add other business-specific resources here
    # For example: resource :dashboard, only: [:show]
    resources :orders, only: [:index, :show] # Add :edit, :update if business users can modify orders
    # ... other business resources
  end

  # CloudFront CDN support for Active Storage
  direct :rails_public_blob do |blob|
    if ENV.fetch("ACTIVE_STORAGE_ASSET_HOST", false) && blob&.key
      File.join(ENV.fetch("ACTIVE_STORAGE_ASSET_HOST"), blob.key)
    else
      route = if blob.is_a?(ActiveStorage::Variant) || blob.is_a?(ActiveStorage::VariantWithRecord)
                :rails_representation
              else
                :rails_blob
              end
      route_for(route, blob)
    end
  end

  # Tip collection routes (token-based for experiences)
  resources :tips, only: [:new, :create, :show] do
    member do
      get :success
    end
  end

  scope module: 'client' do
    get 'dashboard', to: 'dashboard#show', as: :client_dashboard
    resources :bookings, only: [:index, :show]
    # Note: Client estimates are routed via 'my-estimates' path above
  end
end
