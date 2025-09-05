class TenantRedirectController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :redirect_custom_domain_management_paths, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  # Redirect /manage or /admin requests that arrive on a custom domain back to the canonical sub-domain.
  # Example:
  #   https://www.custom.com/manage/dashboard → https://biztest.bizblasts.com/manage/dashboard
  def manage
    business = ActsAsTenant.current_tenant

    # Only custom-domain tenants need redirect.
    if business&.host_type_custom_domain? && business.subdomain.present?
      subdomain_stub = business.dup
      subdomain_stub.host_type = 'subdomain'
      target_url = TenantHost.url_for(subdomain_stub, request, "/manage/#{params[:path]}")
      Rails.logger.info "[TenantRedirectController] Redirecting management path #{request.fullpath} from #{request.host} to #{target_url}"
      return redirect_to target_url, status: :moved_permanently, allow_other_host: true
    end

    # Fallback – show 404 so bots don’t index wrong host.
    render plain: 'Not Found', status: :not_found
  end
end
