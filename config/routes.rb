# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    sessions: 'users/sessions'
  }
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

  # Dashboard for authenticated users
  get "dashboard" => "dashboard#index", as: :dashboard
  
  # Appointments resource with available_slots endpoint
  resources :appointments do
    collection do
      get 'available_slots'
      post 'available_slots'
    end
  end

  # Defines the root path route ("/")
  root "home#index"

  # Fallback route for ActiveAdmin assets
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
      [200, {"Content-Type" => "text/css"}, [content]]
    else
      Rails.logger.error "ActiveAdmin CSS not found in any of: #{possible_paths.join(', ')}"
      [404, {"Content-Type" => "text/plain"}, ["ActiveAdmin CSS not found"]]
    end
  }, constraints: lambda { |req| req.format == :css || req.path.end_with?('.css') }
  
  get "/assets/active_admin-:digest.css", to: proc { |env|
    # Just serve the non-digested version
    file_path = Rails.root.join('public', 'assets', 'active_admin.css')
    
    if File.exist?(file_path)
      content = File.read(file_path)
      [200, {"Content-Type" => "text/css"}, [content]]
    else
      [404, {"Content-Type" => "text/plain"}, ["ActiveAdmin CSS not found"]]
    end
  }, constraints: lambda { |req| req.format == :css || req.path.end_with?('.css') }
end
