class MagicLinkBuilder
  DEFAULT_EXPIRES_IN = 20.minutes

  class << self
    def build_for(user, redirect_path:, remember_me: false, expires_in: DEFAULT_EXPIRES_IN)
      raise ArgumentError, 'user must be present' unless user.present?
      raise ArgumentError, 'redirect_path must start with /' unless redirect_path.to_s.start_with?('/')

      token = user.to_sgid(expires_in: expires_in, for: 'login').to_s

      url_helpers.user_magic_link_url(
        user: {
          email: user.email,
          token: token,
          remember_me: remember_me,
          redirect_to: redirect_path
        },
        **url_options
      )
    end

    private

    def url_options
      action_mailer_options = Rails.application.config.action_mailer.default_url_options
      route_options = Rails.application.routes.default_url_options
      action_mailer_options = action_mailer_options&.symbolize_keys if action_mailer_options
      route_options = route_options&.symbolize_keys if route_options

      action_mailer_options.presence ||
        route_options.presence ||
        { host: 'example.com' }
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end
  end
end

