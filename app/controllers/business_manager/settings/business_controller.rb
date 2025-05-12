# frozen_string_literal: true

class BusinessManager::Settings::BusinessController < ApplicationController # Or your specific base controller for manager sections
  before_action :authenticate_user! # Assuming Devise for authentication
  before_action :set_tenant # ADD THIS LINE to ensure tenant is set
  before_action :set_business
  before_action :authorize_business_settings # Pundit authorization

  layout 'business_manager' # As per global conventions

  def edit
    # @business is set by set_business
    # The view will use @business to populate the form
  end

  def update
    # NOTE: The redirect path helper might need to change if it was based on the old controller name/module.
    # edit_settings_business_path should still work due to how routes are defined.
    if @business.update(business_params)
      redirect_to edit_business_manager_settings_business_path, notice: 'Business information updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_business
    # Assuming current_business is a helper method returning the active tenant/business
    # (e.g., from ActsAsTenant.current_tenant or similar mechanism)
    @business = ActsAsTenant.current_tenant
    raise ActiveRecord::RecordNotFound unless @business
  end

  def authorize_business_settings
    # The policy class is explicitly Settings::BusinessPolicy.
    # If you want this to be BusinessManager::Settings::BusinessPolicy,
    # the policy file would also need to be moved/renamed and its class definition updated.
    # For now, leaving as is, assuming Settings::BusinessPolicy is correctly located and defined.
    authorize @business, :update_settings?, policy_class: Settings::BusinessPolicy
  end

  def business_params
    # Permit base attributes
    permitted = params.require(:business).permit(
      :name, :industry, :phone, :email, :website, :address, :city, :state, :zip, :description, :time_zone, :logo,
      # Permit individual hour fields, which will be processed into a JSON hash
      *days_of_week.flat_map { |day| ["hours_#{day}_open", "hours_#{day}_close"] }
    )

    # Process hours into a JSON structure
    hours_data = {}
    days_of_week.each do |day|
      open_key = "hours_#{day}_open"
      close_key = "hours_#{day}_close"

      open_time = permitted.delete(open_key)
      close_time = permitted.delete(close_key)

      # Store if either open or close time is present for the day
      if open_time.present? || close_time.present?
        hours_data[day.to_sym] = { open: open_time.presence, close: close_time.presence }
      end
    end

    # Assign the structured hours_data to the :hours attribute if it contains any day entries
    permitted[:hours] = hours_data if hours_data.any?

    permitted
  end

  def days_of_week
    %w[mon tue wed thu fri sat sun]
  end
end 