# frozen_string_literal: true

module PolicyEnforcement
  extend ActiveSupport::Concern
  
  included do
    before_action :check_policy_acceptance, unless: :skip_policy_check?
  end
  
  private
  
  def check_policy_acceptance
    return unless current_user&.needs_policy_acceptance?
    
    # Store the intended destination
    session[:after_policy_acceptance_path] = request.fullpath
    
    # For AJAX requests, return JSON response
    if request.xhr?
      render json: { 
        requires_policy_acceptance: true, 
        missing_policies: current_user.missing_required_policies,
        redirect_url: policy_status_path
      }
      return
    end
    
    # For regular requests, the JavaScript modal will handle showing policy acceptance
    # We don't redirect here to avoid disrupting the page flow - the modal is embedded
    # in the application layout and will be shown by the JavaScript on page load
  end
  
  def skip_policy_check?
    # Skip for policy-related pages, authentication pages, etc.
    controller_name == 'policy_acceptances' ||
    controller_name == 'sessions' ||
    controller_name == 'registrations' ||
    action_name == 'policy_acceptance' ||
    request.path.match?(/\/(terms|privacy|privacypolicy|acceptableusepolicy|returnpolicy)/) ||
    request.path.match?(/\/policy_/)
  end
end 