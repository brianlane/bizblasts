# frozen_string_literal: true

class BusinessManager::Settings::ProfilesController < BusinessManager::BaseController
  before_action :set_user, only: [:edit, :update, :destroy, :unsubscribe_all]

  def edit
    authorize @user, policy_class: Settings::ProfilePolicy
    @account_deletion_info = @user.can_delete_account?
    @business_deletion_info = calculate_business_deletion_impact if @user.manager? && @account_deletion_info[:can_delete]
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
      @account_deletion_info = @user.can_delete_account?
      @business_deletion_info = calculate_business_deletion_impact if @user.manager? && @account_deletion_info[:can_delete]
      flash.now[:alert] = 'Failed to update profile.'
      render :edit
    end
  end

  def destroy
    authorize @user, policy_class: Settings::ProfilePolicy

    # Prevent deletion if the user is not the current user
    unless @user == current_user
      head :forbidden and return
    end

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
      # Check if business deletion is required and confirmed
      delete_business = deletion_params[:delete_business] == '1'
      
      # Sign out the user before deletion
      sign_out(@user)
      
      # Delete the account
      result = @user.destroy_account(delete_business: delete_business)
      
      if result[:deleted]
        if result[:business_deleted]
          flash[:notice] = 'Your account and business have been deleted successfully.'
        else
          flash[:notice] = 'Your account has been deleted successfully.'
        end
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

  # Action to unsubscribe from all email notifications
  def unsubscribe_all
    authorize @user, policy_class: Settings::ProfilePolicy # Ensure user is authorized

    # Set all notification preferences to false
    updated_preferences = @user.notification_preferences || {}
    email_preferences = %w[
      email_booking_notifications
      email_order_notifications
      email_customer_notifications
      email_payment_notifications
      email_failed_payment_notifications
      email_subscription_notifications
      email_marketing_notifications
      email_blog_notifications
      email_system_notifications
      email_marketing_updates
      email_blog_updates
    ]
    
    email_preferences.each do |pref|
      updated_preferences[pref] = false
    end

    if @user.update(notification_preferences: updated_preferences)
      redirect_to edit_business_manager_settings_profile_path, notice: 'Unsubscribed from All Emails Successfully.'
    else
      # This case should be rare unless there's a validation on the notification_preferences hash itself
      @account_deletion_info = @user.can_delete_account?
      @business_deletion_info = calculate_business_deletion_impact if @user.manager? && @account_deletion_info[:can_delete]
      flash.now[:alert] = 'Failed to update notification preferences.'
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def calculate_business_deletion_impact
    business = current_user.business
    return nil unless business.present?

    # Only show business deletion info if user is sole user
    other_users = business.users.where.not(id: current_user.id)
    return nil unless other_users.empty?

    {
      business_name: business.name,
      data_counts: {
        services: business.services.count,
        staff_members: business.staff_members.count,
        customers: business.tenant_customers.count,
        bookings: business.bookings.count,
        orders: business.orders.count,
        products: business.products.count,
        invoices: business.invoices.count,
        payments: business.payments.count
      },
      warning_message: "This action will permanently delete your business and all associated data. This cannot be undone."
    }
  end

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

  # For account deletion
  def deletion_params
    params.require(:user).permit(:current_password, :confirm_deletion, :delete_business)
  end
end 