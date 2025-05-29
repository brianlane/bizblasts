# frozen_string_literal: true

class BusinessManager::Settings::ProfilesController < BusinessManager::BaseController
  before_action :set_user, only: [:edit, :update]

  def edit
    authorize @user, policy_class: Settings::ProfilePolicy
  end

  def update
    authorize @user, policy_class: Settings::ProfilePolicy

    # Prevent updates if the user is not the current user (for test edge case)
    unless @user == current_user
      head :forbidden and return
    end

    # Build params for update, exclude password fields if they are blank
    update_params = user_params.except(:password, :password_confirmation)

    if params[:user][:password].present?
      update_params[:password] = params[:user][:password]
      update_params[:password_confirmation] = params[:user][:password_confirmation]
    end

    # Handle notification preferences conversion
    if params[:user][:notification_preferences].present?
      # Handle both Rails form helper and checkbox_tag formats:
      # - Rails form helpers send '1' for checked, '0' for unchecked (simple strings)
      # - checkbox_tag with Rails checkboxes send ['0', '1'] for checked, ['0'] for unchecked
      notification_prefs = {}
      params[:user][:notification_preferences].each do |key, value|
        if value.is_a?(Array)
          # Handle checkbox_tag format: ['0', '1'] = checked, ['0'] = unchecked
          notification_prefs[key] = value.last == '1'
        else
          # Handle Rails form helper format: '1' = checked, '0' = unchecked
          notification_prefs[key] = value == '1'
        end
      end
      update_params[:notification_preferences] = notification_prefs
    else
      # If no notification preferences are submitted at all, preserve existing ones
      # This handles edge cases where the form section might be missing entirely
      update_params[:notification_preferences] = @user.notification_preferences || {}
    end

    if @user.update(update_params)
      # Sign in the user again to reset their session if password was changed.
      # This is a common Devise practice after password updates.
      bypass_sign_in(@user) if params[:user][:password].present?

      redirect_to edit_business_manager_settings_profile_path, notice: 'Profile updated successfully.'
    else
      flash.now[:alert] = 'Failed to update profile.'
      render :edit
    end
  end

  private

  def set_user
    @user = current_user # Assuming current_user is available from Devise/BaseController
  end

  def user_params
    # Permit basic profile attributes and password fields for update.
    # Devise handles if current_password is required or if password fields should be ignored if blank.
    # notification_preferences expects nested attributes for business users.
    params.require(:user).permit(
      :first_name, 
      :last_name, 
      :email, 
      :phone, 
      :password, 
      :password_confirmation,
      notification_preferences: [
        :email_booking_notifications,
        :email_order_notifications, 
        :email_customer_notifications,
        :email_payment_notifications,
        :email_failed_payment_notifications,
        :email_system_notifications,
        :email_marketing_updates
      ]
    )
  end
end 