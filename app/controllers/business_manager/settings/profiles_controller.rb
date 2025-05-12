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
    # notification_preferences expects an array.
    params.require(:user).permit(:first_name, :last_name, :email, :phone, :password, :password_confirmation, notification_preferences: [])
  end
end 