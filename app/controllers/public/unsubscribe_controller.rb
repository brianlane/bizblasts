# frozen_string_literal: true

class Public::UnsubscribeController < Public::BaseController
  include SecurityMonitoring
  skip_before_action :authenticate_user!, only: [:magic_link]
  before_action :find_user_by_email, only: [:magic_link]



  # GET /unsubscribe/magic_link?email=...
  def magic_link
    if @email.blank?
      render json: { error: 'Email parameter required' }, status: :bad_request
      return
    end

    # Check for potential enumeration attack
    check_for_enumeration_attack

    # Always return success to prevent email enumeration attacks
    # If user exists, send magic link; if not, silently do nothing
    user = User.find_by(email: @email)
    if user
      user.send_magic_link(remember_me: false, redirect_url: unsubscribe_settings_path_for_user(user))
      SecureLogger.info "[UNSUBSCRIBE] Magic link sent to existing user: #{@email[0..2]}***"
    else
      SecureLogger.info "[UNSUBSCRIBE] Magic link requested for non-existent email: #{@email[0..2]}***"
    end
    
    # Always return the same response regardless of user existence
    render json: { message: 'If an account with this email exists, a magic link has been sent.' }, status: :ok
  end



  private

  def find_user_by_email
    email = params[:email]
    return if email.blank?
    
    # Always return success to prevent email enumeration
    # Don't expose user existence information
    @email = email
    @user = nil # We'll handle the actual lookup in magic_link method securely
  end

  def unsubscribe_settings_path_for_user(user)
    if user.client?
      edit_client_settings_path
    elsif user.manager? || user.staff?
      '/manage/settings/profile/edit'
    else
      '/'
    end
  end
end 