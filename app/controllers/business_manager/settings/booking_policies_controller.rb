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
    if @booking_policy.update(booking_policy_params)
      redirect_to business_manager_settings_booking_policy_path, notice: 'Booking policies updated successfully.'
    else
      flash.now[:alert] = 'Error updating booking policies.'
      render :edit, status: :unprocessable_entity
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
      :max_daily_bookings,
      :max_advance_days,
      :min_duration_mins,
      :max_duration_mins
    )
  end
end 