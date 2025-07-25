module BusinessManager
  module Settings
    class IntegrationsController < BusinessManager::BaseController
      include SecurityMonitoring
      before_action :set_business
      before_action :set_integration, only: [:show, :edit, :update, :destroy]

      def index
        @integrations = policy_scope([:business_manager, :settings, @business.integrations])
        authorize [:business_manager, :settings, Integration]
      end

      def show
        authorize [:business_manager, :settings, @integration]
      end

      def new
        @integration = @business.integrations.build
        authorize [:business_manager, :settings, @integration]
      end

      def create
        @integration = @business.integrations.build(integration_params)
        authorize [:business_manager, :settings, @integration]
        if @integration.save
          redirect_to business_manager_settings_integrations_path, notice: 'Integration was successfully created.'
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize [:business_manager, :settings, @integration]
      end

      def update
        authorize [:business_manager, :settings, @integration]
        if @integration.update(integration_params)
          redirect_to business_manager_settings_integrations_path, notice: 'Integration was successfully updated.'
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize [:business_manager, :settings, @integration]
        @integration.destroy
        redirect_to business_manager_settings_integrations_url, notice: 'Integration was successfully deleted.'
      end

      private

      def set_business
        @business = current_business
        # Ensure business is present, redirect or raise error if not
        unless @business
          flash[:alert] = "Business not found."
          redirect_to root_path # Or some other appropriate path
        end
      end

      def set_integration
        @integration = @business.integrations.find(params[:id])
      end

      def integration_params
        params.require(:integration).permit(:kind, config: {})
      end
    end
  end
end 