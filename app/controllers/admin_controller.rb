class AdminController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :authenticate_admin_user!
  
  # Skip tenant setup for admin users
  # skip_before_action :set_tenant # REMOVED: Global filter was removed
  
  # This controller serves as a base for any custom admin controllers
  # that are not part of ActiveAdmin but need admin authentication
end 