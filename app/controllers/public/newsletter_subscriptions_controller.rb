module Public
  class NewsletterSubscriptionsController < ApplicationController
    skip_before_action :authenticate_user!

    def create
      email = params.dig(:newsletter_subscription, :email).to_s.strip

      if email.blank?
        flash[:alert] = "Please provide an email address."
        return redirect_back(fallback_location: tenant_root_path)
      end

      begin
        linker = CustomerLinker.new(current_tenant)
        linker.find_or_create_guest_customer(email)
        flash[:notice] = "Thanks! You're on the list."
      rescue GuestConflictError => e
        flash[:alert] = e.message
      rescue StandardError => e
        Rails.logger.error "[NewsletterSubscriptionsController] Failed to subscribe email #{email} for business #{current_tenant&.id}: #{e.message}"
        flash[:alert] = "We couldn't add your email right now. Please try again."
      end

      redirect_back fallback_location: tenant_root_path
    end
  end
end

