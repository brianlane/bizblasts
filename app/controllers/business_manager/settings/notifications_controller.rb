module BusinessManager
  module Settings
    class NotificationsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_business

      layout 'business_manager'

      def index
        @notification_templates = policy_scope([:business_manager, :settings, @business.notification_templates])
        @integration_credentials = policy_scope([:business_manager, :settings, @business.integration_credentials])
      end

      def new
        @notification_template = @business.notification_templates.build
        authorize [:business_manager, :settings, @notification_template]
      end

      def create
        @notification_template = @business.notification_templates.build(notification_template_params)
        authorize [:business_manager, :settings, @notification_template]
        if @notification_template.save
          redirect_to business_manager_settings_notifications_path, notice: 'Notification template created successfully.'
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @notification_template = @business.notification_templates.find(params[:id])
        authorize [:business_manager, :settings, @notification_template]
      end

      def update
        @notification_template = @business.notification_templates.find(params[:id])
        authorize [:business_manager, :settings, @notification_template]
        if @notification_template.update(notification_template_params)
          redirect_to business_manager_settings_notifications_path, notice: 'Notification template updated successfully.'
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @notification_template = @business.notification_templates.find(params[:id])
        authorize [:business_manager, :settings, @notification_template]
        @notification_template.destroy
        redirect_to business_manager_settings_notifications_url, notice: 'Notification template deleted successfully.'
      end

      def edit_credentials
        @integration_credentials = @business.integration_credentials
        # Authorize access to integration credentials
        authorize [:business_manager, :settings, @integration_credentials.build], :edit_credentials?

        if @integration_credentials.empty?
          redirect_to business_manager_settings_notifications_path, alert: 'No integration credentials found to edit.'
        end
      end

      def update_credentials
        # Logic to update credentials - this might be complex depending on how many credentials there are
        # For now, a basic structure assuming updating existing ones or creating if none exist
        # This will likely need refinement based on the actual form structure and multiple providers
        @integration_credentials = @business.integration_credentials
        # Example: iterate through params to find and update/create credentials
        # This part requires knowing the structure of the form for credentials

        # Placeholder for update logic
        # if success
        #   redirect_to business_manager_settings_notifications_path, notice: 'Integration credentials updated successfully.'
        # else
        #   render :edit_credentials
        # end
         redirect_to business_manager_settings_notifications_path, notice: 'Integration credentials update logic needs implementation.'
      end

      private

      def set_business
        @business = current_user.business
      end

      def notification_template_params
        params.require(:notification_template).permit(:event_type, :channel, :subject, :body)
      end

      # Parameters for updating credentials - requires knowledge of form structure
      # def integration_credential_params
      #   params.require(:integration_credential).permit(:provider, config: {})
      # end
    end
  end
end 