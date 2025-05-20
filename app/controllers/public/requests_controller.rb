module Public
  class RequestsController < ApplicationController
    before_action :set_tenant
    skip_before_action :authenticate_user!

    def create
      # Stub action: after form submission, redirect back with a notice
      redirect_to tenant_estimate_page_path, notice: 'Thank you for your request. We will be in touch soon.'
    end

    private

    def set_tenant
      # Ensure tenant is set based on subdomain
      ActsAsTenant.current_tenant = Business.find_by(subdomain: request.subdomain)
    end
  end
end 