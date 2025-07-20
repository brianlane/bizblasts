# frozen_string_literal: true

class Public::UnsubscribeController < Public::BaseController
  skip_before_action :authenticate_user!, only: [:magic_link]
  before_action :find_user_by_email, only: [:magic_link]



  # GET /unsubscribe/magic_link?email=...
  def magic_link
    if @user.nil?
      render json: { error: 'User not found' }, status: :not_found
      return
    end

    # Generate magic link token and send magic link email for unsubscribe
    @user.send_magic_link(remember_me: false, redirect_url: unsubscribe_settings_path_for_user(@user))
    
    render json: { message: 'Magic link sent to your email' }, status: :ok
  end



  private

  def find_user_by_email
    email = params[:email]
    return if email.blank?
    
    @user = User.find_by(email: email)
  end

  def unsubscribe_settings_path_for_user(user)
    if user.client?
      '/client/settings'
    elsif user.manager? || user.staff?
      '/manage/settings/profile/edit'
    else
      '/'
    end
  end
end 