# frozen_string_literal: true

module PolicyEnforcement
  extend ActiveSupport::Concern
  
  included do
    before_action :check_policy_acceptance, unless: :skip_policy_check?
  end
  
  private
  
  def check_policy_acceptance
    # OPTIMIZATION: Skip policy checking entirely for users who have completed all policies
    return unless current_user
    
    # Fast path: If user doesn't need policy acceptance, skip all checks
    unless current_user.requires_policy_acceptance?
      # Only perform the more expensive missing_required_policies check if the flag indicates they might need it
      return unless current_user.missing_required_policies.any?
      
      # If missing policies found but flag was false, update the flag (edge case)
      current_user.update_column(:requires_policy_acceptance, true)
    end
    
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
    request.path.match?(/\/policy_/) ||
    # Skip for AJAX requests to policy_status to avoid duplicate checking
    (request.xhr? && request.path == '/policy_status')
  end
end 