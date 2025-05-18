# frozen_string_literal: true

class Client::SettingsController < ApplicationController # Changed from Client::BaseController
  before_action :authenticate_user! # Added Devise authentication
  before_action :set_user, only: [:show, :edit, :update]
  before_action -> { authorize @user, policy_class: Client::SettingsPolicy }

  def show
    # @user is set by before_action
    render :edit # Or :show, depending on view file name
  end

  def edit
    # @user is set by before_action
  end

  def update
    # Using user_params to determine which update method to use
    # Check if password fields are submitted and not blank
    if params.dig(:user, :password).present?
      # Password update attempt
      if @user.update_with_password(password_update_params)
        bypass_sign_in(@user)
        redirect_to client_settings_path, notice: 'Settings (including password) updated successfully.'
      else
        flash.now[:alert] = 'Failed to update password. Please check your current password and ensure new passwords match.'
        render :edit, status: :unprocessable_entity
      end
    else
      # Profile update only (no password change)
      # Remove password parameters to avoid unpermitted params warning
      if @user.update(profile_update_params)
        redirect_to client_settings_path, notice: 'Profile settings updated successfully.'
      else
        flash.now[:alert] = 'Failed to update profile settings.'
        render :edit, status: :unprocessable_entity
      end
    end
  end

  private

  def set_user
    @user = current_user
  end

  # For profile updates without password
  def profile_update_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :email,
      :phone,
      notification_preferences: [:email_booking_confirmation, :sms_booking_reminder, :email_promotions, :sms_promotions, :email_order_updates, :sms_order_updates]
      # Add other specific keys for notification_preferences as they are defined
    )
  end

  # For password updates (requires current_password)
  def password_update_params
    params.require(:user).permit(
      :password,
      :password_confirmation,
      :current_password
    )
  end

  # Combined params if needed elsewhere, or for initial permitting before splitting logic
  def user_params
     params.require(:user).permit(
      :first_name,
      :last_name,
      :email,
      :phone,
      :password,
      :password_confirmation,
      :current_password,
      notification_preferences: [:email_booking_confirmation, :sms_booking_reminder, :email_promotions, :sms_promotions, :email_order_updates, :sms_order_updates]
    )
  end
end 