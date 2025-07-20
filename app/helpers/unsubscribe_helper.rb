# frozen_string_literal: true

module UnsubscribeHelper
  # Generate a magic link URL that will sign in the user and redirect to their unsubscribe settings
  def unsubscribe_magic_link_for(user)
    return root_url unless user.present?

    # Determine the redirect path based on user role
    if user.client?
      redirect_path = edit_client_settings_path
    elsif user.manager? || user.staff?
      # For manager/staff users, redirect directly to their business settings profile page
      # This will be handled by the magic links controller with cross-domain redirect
      redirect_path = '/manage/settings/profile/edit'
    else
      redirect_path = root_path
    end

    # Generate a magic link token using the same approach as the magic link mailer
    # This creates a signed global ID token that can be used for magic link authentication
    token = user.to_sgid(expires_in: 20.minutes, for: 'login').to_s

    # Generate the magic link URL using the same format as the devise mailer
    # This will directly authenticate the user and redirect them
    user_magic_link_url(
      user: {
        email: user.email,
        token: token,
        redirect_to: redirect_path
      }
    )
  end
end
