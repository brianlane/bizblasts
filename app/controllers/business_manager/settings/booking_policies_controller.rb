# frozen_string_literal: true

# Assuming a base controller like BusinessManager::BaseController exists
# and provides `current_business` and Pundit authorization.

class BusinessManager::Settings::BookingPoliciesController < BusinessManager::BaseController # Adjust if base controller name differs
  before_action :set_booking_policy, only: [:show, :edit, :update]
  after_action :verify_authorized

  def show
    authorize @booking_policy, policy_class: BusinessManager::Settings::BookingPolicyPolicy
    # Render view
  end

  def edit
    authorize @booking_policy, policy_class: BusinessManager::Settings::BookingPolicyPolicy
    # Render view
  end

  def update
    authorize @booking_policy, policy_class: BusinessManager::Settings::BookingPolicyPolicy
    
    # Convert hours to minutes for cancellation_window_hours before updating
    processed_params = booking_policy_params.dup
    if processed_params[:cancellation_window_hours].present?
      hours = processed_params[:cancellation_window_hours].to_i
      processed_params[:cancellation_window_mins] = hours * 60
    else
      processed_params[:cancellation_window_mins] = nil
    end
    
    # Convert hours to minutes for min_advance_hours before updating
    if processed_params[:min_advance_hours].present?
      hours = processed_params[:min_advance_hours].to_i
      processed_params[:min_advance_mins] = hours * 60
    else
      processed_params[:min_advance_mins] = nil
    end
    
    # Remove the virtual parameters
    processed_params.delete(:cancellation_window_hours)
    processed_params.delete(:min_advance_hours)

    # Normalize service radius fields
    unless processed_params[:service_radius_enabled] == '1' || processed_params[:service_radius_enabled] == true
      processed_params[:service_radius_enabled] = false
    else
      processed_params[:service_radius_enabled] = true
    end

    processed_params[:service_radius_miles] = processed_params[:service_radius_miles].presence&.to_i
    
    if @booking_policy.update(processed_params)
      redirect_to business_manager_settings_booking_policy_path, notice: 'Booking policies updated successfully.'
    else
      flash.now[:alert] = 'Error updating booking policies.'
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_booking_policy
    # Find existing or build new for edit/update if none exists
    @booking_policy = current_business.booking_policy || current_business.build_booking_policy
  end

  def booking_policy_params
    params.require(:booking_policy).permit(
      :cancellation_window_mins,
      :buffer_time_mins,
      :min_advance_mins,
      :max_daily_bookings,
      :max_advance_days,
      :min_duration_mins,
      :max_duration_mins,
      :cancellation_window_hours,
      :min_advance_hours,
      :auto_confirm_bookings,
      :use_fixed_intervals,
      :interval_mins,
      :service_radius_enabled,
      :service_radius_miles
    )
  end
end 