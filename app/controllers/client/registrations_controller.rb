# frozen_string_literal: true

# Handles client user sign-ups.
class Client::RegistrationsController < Users::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]

  protected

  # Permit additional parameters for client sign-up.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
    # Role is automatically set to client by default in the model
  end

  # Override the build_resource method to ensure the role is explicitly client
  # This prevents someone from trying to inject a different role via params
  def build_resource(hash = {})
    super(hash)
    self.resource.role = :client
  end

  # Optional: Override path after sign up if needed
  # def after_sign_up_path_for(resource)
  #   # e.g., client_dashboard_path
  #   super(resource)
  # end
end 