class BusinessManager::Settings::TipsController < BusinessManager::BaseController
  before_action :ensure_business_manager!
  
  def show
    @business = current_business
    @tip_configuration = @business.tip_configuration_or_default
  end
  
  def update
    @business = current_business
    @tip_configuration = @business.tip_configuration_or_default
    
    ActiveRecord::Base.transaction do
      # Update business tips_enabled setting
      @business.update!(tips_params)
      
      # Update or create tip configuration if provided
      if tip_configuration_params.present?
        if @tip_configuration.persisted?
          @tip_configuration.update!(tip_configuration_params)
        else
          @business.create_tip_configuration!(tip_configuration_params)
        end
      end
      
      # Update individual product/service tip settings if provided
      update_product_tip_settings if product_tip_params.present?
      update_service_tip_settings if service_tip_params.present?
    end
    
    flash[:notice] = "Tips settings updated successfully."
    redirect_to business_manager_settings_tips_path
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Unable to update tips settings: #{e.record.errors.full_messages.join(', ')}"
    render :show
  end
  
    private

  def tips_params
    params.require(:business).permit(:tips_enabled)
  end
  
  def tip_configuration_params
    return {} unless params[:tip_configuration].present?
    
    params.require(:tip_configuration).permit(
      :custom_tip_enabled,
      :tip_message,
      default_tip_percentages: []
    )
  end
  
  def product_tip_params
    return {} unless params[:products].present?
    
    params.require(:products).permit!
  end
  
  def service_tip_params
    return {} unless params[:services].present?
    
    params.require(:services).permit!
  end
  
  def update_product_tip_settings
    product_tip_params.each do |product_id, settings|
      product = current_business.products.find(product_id)
      product.update!(tips_enabled: settings[:tips_enabled])
    end
  end
  
  def update_service_tip_settings
    service_tip_params.each do |service_id, settings|
      service = current_business.services.find(service_id)
      service.update!(tips_enabled: settings[:tips_enabled])
    end
  end

  def ensure_business_manager!
    unless current_user.business_manager?(current_business)
      respond_to do |format|
        format.html do
          flash[:alert] = 'You are not authorized to access this page.'
          redirect_to root_path
        end
        format.json do
          render json: { error: 'Unauthorized' }, status: :forbidden
        end
      end
    end
  end
end 