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
end
