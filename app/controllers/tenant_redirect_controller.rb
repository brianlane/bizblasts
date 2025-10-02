class TenantRedirectController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :redirect_custom_domain_management_paths, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  # Redirect /manage or /admin requests that arrive on a custom domain back to the canonical sub-domain.
  # Example:
  #   https://www.custom.com/manage/dashboard → https://biztest.bizblasts.com/manage/dashboard
  #
  # Note: This controller now serves as a fallback for unauthenticated users only.
  # Authenticated users are handled by the custom domain business manager routes.
  def manage
    business = ActsAsTenant.current_tenant

    # Only custom-domain tenants need redirect consideration
    if business&.host_type_custom_domain? && business.subdomain.present?
      # This controller should only be reached by unauthenticated users now
      # since authenticated users are handled by custom domain business manager routes
      Rails.logger.info "[TenantRedirectController] Unauthenticated user on custom domain #{request.host}, redirecting to subdomain for authentication"

      subdomain_stub = business.dup
      subdomain_stub.host_type = 'subdomain'

      # Use the original fullpath (includes leading /manage and query string) to avoid losing params
      target_url = TenantHost.url_for(subdomain_stub, request, request.fullpath)
      Rails.logger.info "[TenantRedirectController] Redirecting management path #{request.fullpath} from #{request.host} to #{target_url}"
      return redirect_to target_url, status: :moved_permanently, allow_other_host: true
    end

    # Fallback – show 404 so bots don't index wrong host.
    render plain: 'Not Found', status: :not_found
  end
end
