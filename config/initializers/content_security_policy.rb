# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data, "blob:"
    policy.object_src  :none
    policy.script_src  :self, :https, :unsafe_inline, :unsafe_eval, "https://app.termly.io"
    policy.style_src   :self, :https, :unsafe_inline
    policy.connect_src :self, :https, "wss:", "ws:"
    policy.frame_src   :self, :https, "https://app.termly.io"
    policy.media_src   :self, :https, :data, "blob:"
    
    # Allow ActiveAdmin and other admin interfaces
    policy.script_src_elem :self, :https, :unsafe_inline, "https://app.termly.io"
    policy.style_src_elem :self, :https, :unsafe_inline
    
    # Specify URI for violation reports (optional)
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Start in report-only mode to test compatibility
  config.content_security_policy_report_only = true
end
