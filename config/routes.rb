# frozen_string_literal: true

require Rails.root.join('lib/constraints/subdomain_constraint')

Rails.application.routes.draw do
  # Add routes for admin bookings availability before ActiveAdmin is initialized
  get '/admin/bookings-availability/slots', to: 'admin/booking_availability#available_slots', as: :available_slots_bookings
  get '/admin/bookings-availability/new', to: 'admin/booking_availability#new', as: :new_admin_booking_from_slots
  
  # Debug route to test available slots
  get '/debug/available-slots', to: 'admin/booking_availability#available_slots'
  
  # ActiveAdmin routes
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  
  devise_for :users, skip: [:registrations], controllers: {
    sessions: 'users/sessions',
  }

  devise_for :businesses, skip: [:registrations], controllers: {
    sessions: 'businesses/sessions',
  }

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

  constraints(SubdomainConstraint) do
    namespace :business_manager, path: '/manage' do
      get '/dashboard', to: 'dashboard#index', as: :dashboard
      resources :services
      resources :products
      resources :shipping_methods
      resources :tax_rates
      resources :staff_members do
        member do
          get 'manage_availability'
          patch 'manage_availability'
        end
      end
      
      # Bookings management
      resources :bookings, only: [:index, :show, :edit, :update] do
        member do
          patch 'confirm'
          patch 'cancel'
          get 'reschedule'
          patch 'update_schedule'
        end
        collection do
          get '/available-slots', to: 'bookings#available_slots', as: :available_slots
        end
      end
      
      # Add route for available slots in business manager context
      get '/available-slots', to: 'bookings#available_slots', as: :available_slots_bookings

      # Allow staff/manager to create bookings under subdomain
      resources :client_bookings, only: [:new, :create], path: 'my-bookings'
      
      # Business orders management
      resources :orders, only: [:index, :show]
    end

    # Business-specific routes for business owners
    namespace :business do
      resources :orders, only: [:index, :show]
    end

    scope module: 'public' do
      get '/', to: 'pages#show', constraints: { page: /home|root|^$/ }, as: :tenant_root
      get '/about', to: 'pages#show', page: 'about', as: :tenant_about_page
      get '/services', to: 'pages#show', page: 'services', as: :tenant_services_page
      get '/products', to: 'pages#show', page: 'products', as: :tenant_products_page
      get '/contact', to: 'pages#show', page: 'contact', as: :tenant_contact_page

      get '/calendar', to: 'tenant_calendar#index', as: :tenant_calendar
      get '/available-slots', to: 'tenant_calendar#available_slots', as: :tenant_available_slots
      get '/staff-availability', to: 'tenant_calendar#staff_availability', as: :tenant_staff_availability

      get '/book', to: 'booking#new', as: :new_tenant_booking
      resources :booking, only: [:create], as: :tenant_bookings
      get '/booking/:id/confirmation', to: 'booking#confirmation', as: :tenant_booking_confirmation

      get '/my-bookings', to: 'client_bookings#index', as: :tenant_my_bookings
      get '/my-bookings/:id', to: 'client_bookings#show', as: :tenant_my_booking, constraints: { id: /\d+/ }
      patch '/my-bookings/:id/cancel', to: 'client_bookings#cancel', as: :cancel_tenant_my_booking, constraints: { id: /\d+/ }

      resources :invoices, only: [:index, :show], as: :tenant_invoices
      resources :payments, only: [:index, :new, :create], as: :tenant_payments

      resources :products, only: [:index, :show]
      resource :cart, only: [:show], controller: 'carts'
      resources :line_items, only: [:create, :update, :destroy]
      resources :orders, only: [:new, :create, :show, :index], as: :tenant_orders
      # Catch-all for static pages must come last
      get '/:page', to: 'pages#show', as: :tenant_page
    end
  end

  resources :businesses, only: [:index]
  root "home#index"

  get "up" => "rails/health#show", as: :rails_health_check
  get "healthcheck" => "health#check", as: :health_check
  get "db-check" => "health#db_check", as: :db_check
  get "maintenance" => "maintenance#index", as: :maintenance
  get "home/debug" => redirect("/admin/debug"), as: :old_tenant_debug
  get "admin/debug" => "admin/debug#index", as: :tenant_debug

  authenticated :user do
    root 'home#index', as: :authenticated_root
  end

  authenticated :user, ->(user) { user.client? } do
    get 'dashboard', to: 'client_dashboard#index'
    resources :client_bookings, path: 'my-bookings' do
      member do
        patch 'cancel'
      end
    end
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

  # Add public product/order/cart routes for testability and non-subdomain access
  resources :products, only: [:index, :show]
  resource :cart, only: [:show]
  resources :line_items, only: [:create, :update, :destroy]
  resources :orders, only: [:new, :create, :show, :index]

  namespace :business_portal do
    # Add other business-specific resources here
    # For example: resource :dashboard, only: [:show]
    resources :orders, only: [:index, :show] # Add :edit, :update if business users can modify orders
    # ... other business resources
  end
end
