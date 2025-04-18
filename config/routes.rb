# frozen_string_literal: true

require Rails.root.join('lib/constraints/subdomain_constraint')

Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  devise_for :users, skip: [:registrations], controllers: {
    sessions: 'users/sessions',
    # Add other controllers like passwords, confirmations if needed
  }

  devise_for :businesses, skip: [:registrations], controllers: {
    sessions: 'businesses/sessions',
    # Add other controllers if needed
  }

  # Scoped Devise routes for specific registration flows
  devise_scope :user do
    # Client Registration Routes
    get '/client/sign_up', to: 'client/registrations#new', as: :new_client_registration
    post '/client', to: 'client/registrations#create', as: :client_registration

    # Business Registration Routes
    get '/business/sign_up', to: 'business/registrations#new', as: :new_business_registration
    post '/business', to: 'business/registrations#create', as: :business_registration

    # Routes for editing user registration, canceling etc. might still use the base controller
    # or could be scoped further if client/business edit flows differ significantly.
    # Example using base controller:
    get '/users/edit', to: 'users/registrations#edit', as: :edit_user_registration
    patch '/users', to: 'users/registrations#update', as: :user_registration # Note: default path used by Devise form helpers
    put '/users', to: 'users/registrations#update' # Allow PUT as well
    delete '/users', to: 'users/registrations#destroy'

    # Route for signing out via GET
    get '/users/sign_out', to: 'users/sessions#destroy'
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  
  # Custom health check endpoint for Render
  get "healthcheck" => "health#check", as: :health_check
  
  # Database connectivity check endpoint
  get "db-check" => "health#db_check", as: :db_check
  
  # Maintenance page that doesn't require database access
  get "maintenance" => "maintenance#index", as: :maintenance

  # Add debug route to test multi-tenancy
  get "home/debug" => redirect("/admin/debug"), as: :old_tenant_debug
  get "admin/debug" => "admin/debug#index", as: :tenant_debug

  # General authenticated routes
  authenticated :user do
    # Commenting out the generic dashboard route to avoid conflict with tenant/admin/client dashboards
    # get 'dashboard', to: 'dashboard#index' 
    # Point authenticated root to the main home page, rely on after_sign_in_path_for for role-based redirect
    root 'home#index', as: :authenticated_root 
  end

  authenticated :user, ->(user) { user.client? } do
    get 'dashboard', to: 'client_dashboard#index'
  end

  authenticated :user, ->(user) { user.admin? } do
    get 'dashboard', to: 'admin_dashboard#index'
  end

  # Bookings resource with available_slots endpoint
  resources :bookings, except: [:new] do
    collection do
      get 'available_slots'
      post 'available_slots'
    end
  end

  # Defines the root path route ("/")
  root "home#index"

  # Serve all assets from public directory with digest (application-123abc.css)
  get "/assets/:name-:digest.:format", to: proc { |env|
    name = env["action_dispatch.request.path_parameters"][:name]
    format = env["action_dispatch.request.path_parameters"][:format]
    
    # Construct both digested and non-digested filenames
    digested_filename = "#{name}-#{env["action_dispatch.request.path_parameters"][:digest]}.#{format}"
    non_digested_filename = "#{name}.#{format}"
    
    # Try to find the file in multiple locations
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
  
  # Serve all non-digested assets from public directory (application.css)
  get "/assets/:filename", to: proc { |env|
    filename = env["action_dispatch.request.path_parameters"][:filename]
    
    # Try to find the file in multiple locations
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
  
  # Special routes for ActiveAdmin CSS (these are more specific and will match first)
  get "/assets/active_admin.css", to: proc { |env|
    # Try to find the file in multiple locations
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
  
  # Handle digested version of ActiveAdmin CSS
  get "/assets/active_admin-:digest.css", to: proc { |env|
    # Just serve the non-digested version
    file_path = Rails.root.join('public', 'assets', 'active_admin.css')
    
    if File.exist?(file_path)
      content = File.read(file_path)
      [200, {"Content-Type" => "text/css", "Cache-Control" => "public, max-age=31536000"}, [content]]
    else
      [404, {"Content-Type" => "text/plain"}, ["ActiveAdmin CSS not found"]]
    end
  }

  # Multi-Tenant Business Routes (accessed via subdomain/custom domain)
  # Remove constraint in test env as it causes issues with system tests
  if !Rails.env.test?
    constraints(SubdomainConstraint) do
      scope module: 'business_manager' do
        get '/dashboard', to: 'dashboard#index', as: :business_manager_dashboard
        resources :services, except: [:show] # Add routes for services CRUD

        # Add other business manager specific routes here
      end
    end
  else # In test environment, define routes without constraint
    scope module: 'business_manager' do
      get '/dashboard', to: 'dashboard#index', as: :business_manager_dashboard
      resources :services, except: [:show]
      # Add other business manager specific routes here
    end
  end

  # Public facing tenant website routes - Keep constraint here
  constraints(SubdomainConstraint) do
    scope module: 'public' do
      get '/', to: 'pages#show', constraints: { page: /home|root|^$/ }, as: :tenant_root
      get '/about', to: 'pages#show', page: 'about'
      get '/services', to: 'pages#show', page: 'services'
      get '/contact', to: 'pages#show', page: 'contact'
      # Add routes for booking, dynamic pages etc.
      get '/book', to: 'booking#new', as: :new_booking
      resources :booking, only: [:create]
      get '/:page', to: 'pages#show', as: :tenant_page
    end
  end
end
