class BusinessManager::PromotionsController < BusinessManager::BaseController
  before_action :set_promotion, only: [:show, :edit, :update, :destroy, :toggle_status]
  
  def index
    @promotions = current_business.promotions.order(created_at: :desc)
    @active_promotions = @promotions.active
    @upcoming_promotions = @promotions.upcoming
    @expired_promotions = @promotions.expired
  end
  
  def show
    @promotion_stats = {
      total_usage: @promotion.current_usage,
      remaining_usage: @promotion.usage_limit ? (@promotion.usage_limit - @promotion.current_usage) : nil,
      redemptions: @promotion.promotion_redemptions.includes(:tenant_customer),
      revenue_impact: calculate_revenue_impact
    }
  end
  
  def new
    @promotion = current_business.promotions.build
    @products = current_business.products.active
    @services = current_business.services.active
  end
  
  def create
    @promotion = current_business.promotions.build(promotion_params)
    
    if @promotion.save
      # Handle product and service associations
      handle_product_associations
      handle_service_associations
      
      redirect_to business_manager_promotion_path(@promotion), 
                  notice: 'Promotion was successfully created and is now live!'
    else
      @products = current_business.products.active
      @services = current_business.services.active
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
    @products = current_business.products.active
    @services = current_business.services.active
  end
  
  def update
    if @promotion.update(promotion_params)
      # Handle product and service associations
      handle_product_associations
      handle_service_associations
      
      redirect_to business_manager_promotion_path(@promotion), 
                  notice: 'Promotion was successfully updated!'
    else
      @products = current_business.products.active
      @services = current_business.services.active
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @promotion.destroy
    redirect_to business_manager_promotions_path, 
                notice: 'Promotion was successfully deleted.'
  end
  
  def toggle_status
    @promotion.update!(active: !@promotion.active?)
    status_text = @promotion.active? ? 'activated' : 'deactivated'
    redirect_to business_manager_promotions_path, 
                notice: "Promotion was successfully #{status_text}."
  end

  def bulk_deactivate
    promotion_ids = params[:promotion_ids] || []
    updated_count = 0
    
    promotion_ids.each do |promotion_id|
      promotion = current_business.promotions.find_by(id: promotion_id)
      if promotion&.active?
        promotion.update!(active: false)
        updated_count += 1
      end
    end
    
    redirect_to business_manager_promotions_path, 
                notice: "Successfully deactivated #{updated_count} promotion#{'s' if updated_count != 1}."
  end
  
  private
  
  def set_promotion
    @promotion = current_business.promotions.find(params[:id])
  end
  
  def promotion_params
    params.require(:promotion).permit(
      :name, :code, :description, :discount_type, :discount_value,
      :start_date, :end_date, :usage_limit, :active,
      :applicable_to_products, :applicable_to_services,
      :public_dates, :allow_discount_codes,
      product_ids: [], service_ids: []
    )
  end
  
  def handle_product_associations
    return unless params[:promotion][:product_ids].present?
    
    # Clear existing associations
    @promotion.promotion_products.destroy_all
    
    # Create new associations
    product_ids = params[:promotion][:product_ids].reject(&:blank?)
    product_ids.each do |product_id|
      @promotion.promotion_products.create!(product_id: product_id)
    end
  end
  
  def handle_service_associations
    return unless params[:promotion][:service_ids].present?
    
    # Clear existing associations
    @promotion.promotion_services.destroy_all
    
    # Create new associations
    service_ids = params[:promotion][:service_ids].reject(&:blank?)
    service_ids.each do |service_id|
      @promotion.promotion_services.create!(service_id: service_id)
    end
  end
  
  def calculate_revenue_impact
    # Calculate total discount given through this promotion
    @promotion.promotion_redemptions.joins(:booking, :invoice)
             .sum('COALESCE(bookings.promo_discount_amount, 0) + COALESCE(invoices.discount_amount, 0)')
  rescue
    0
  end
end 