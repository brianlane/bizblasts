module BusinessManager
  module Settings
    class WebsitePagesController < BusinessManager::BaseController
      before_action :authenticate_user!
      before_action :set_business
      before_action :authorize_business_settings

      layout 'business_manager'

      def edit
      end

      def update
        if @business.update(website_pages_params)
          redirect_to edit_business_manager_settings_website_pages_path, notice: 'Website pages settings updated.'
        else
          render :edit, status: :unprocessable_content
        end
      end

      private

      def set_business
        # Use ActsAsTenant or fall back to current_user.business
        @business = ActsAsTenant.current_tenant || current_user.business
        raise ActiveRecord::RecordNotFound unless @business
      end

      def authorize_business_settings
        # Use the top-level Settings::BusinessPolicy for business settings authorization
        authorize @business, :update_settings?, policy_class: ::Settings::BusinessPolicy
      end

      def website_pages_params
        params.require(:business).permit(
          :show_services_section,
          :show_products_section,
          :show_estimate_page,
          :website_layout,
          :enhanced_accent_color,
          :facebook_url,
          :twitter_url,
          :instagram_url,
          :pinterest_url,
          :linkedin_url,
          :tiktok_url,
          :youtube_url
        )
      end
    end
  end
end 