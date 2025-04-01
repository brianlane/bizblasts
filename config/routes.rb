# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users
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

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Add debug route to test multi-tenancy
  get "home/debug" => "home#debug", as: :tenant_debug

  # Defines the root path route ("/")
  root "home#index"
end
