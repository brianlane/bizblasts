# frozen_string_literal: true

class Client::SettingsController < ApplicationController # Changed from Client::BaseController
  before_action :authenticate_user! # Added Devise authentication
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  before_action :authorize_user, only: [:show, :edit, :update, :destroy]

  def show
    # @user is set by before_action
    @account_deletion_info = @user.can_delete_account?
    render :edit # Or :show, depending on view file name
  end

  def edit
    # @user is set by before_action
    @account_deletion_info = @user.can_delete_account?
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

  def destroy
    # Validate current password
    unless @user.valid_password?(deletion_params[:current_password])
      flash.now[:alert] = 'Current password is incorrect.'
      @account_deletion_info = @user.can_delete_account?
      render :edit, status: :unprocessable_entity
      return
    end

    # Validate deletion confirmation
    unless deletion_params[:confirm_deletion] == 'DELETE'
      flash.now[:alert] = 'You must type DELETE to confirm account deletion.'
      @account_deletion_info = @user.can_delete_account?
      render :edit, status: :unprocessable_entity
      return
    end

    begin
      # Sign out the user before deletion
      sign_out(@user)
      
      # Delete the account
      result = @user.destroy_account
      
      if result[:deleted]
        flash[:notice] = 'Your account has been deleted successfully.'
        redirect_to root_path
      else
        flash[:alert] = 'Failed to delete account. Please try again.'
        redirect_to root_path
      end
    rescue User::AccountDeletionError => e
      # Re-sign in the user since we signed them out
      sign_in(@user)
      flash.now[:alert] = e.message
      @account_deletion_info = @user.can_delete_account?
      render :edit, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Account deletion failed for user #{@user.id}: #{e.message}"
      # Re-sign in the user since we signed them out
      sign_in(@user)
      flash.now[:alert] = 'An error occurred while deleting your account. Please contact support.'
      @account_deletion_info = @user.can_delete_account?
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = current_user
  end

  def authorize_user
    authorize @user, policy_class: Client::SettingsPolicy
  end

  # For profile updates without password
  def profile_update_params
    params.require(:user).permit(
      :first_name, 
      :last_name, 
      :phone,
      notification_preferences: [
        :email_booking_confirmation,
        :sms_booking_reminder,
        :email_order_updates,
        :sms_order_updates,
        :email_promotions,
        :sms_promotions
      ]
    )
  end

  # For password updates (include current_password for verification)
  def password_update_params
    params.require(:user).permit(
      :first_name, 
      :last_name, 
      :phone, 
      :current_password,
      :password, 
      :password_confirmation,
      notification_preferences: [
        :email_booking_confirmation,
        :sms_booking_reminder,
        :email_order_updates,
        :sms_order_updates,
        :email_promotions,
        :sms_promotions
      ]
    )
  end

  # For account deletion
  def deletion_params
    params.require(:user).permit(:current_password, :confirm_deletion)
  end
end 