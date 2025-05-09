module BusinessManager
  class ShippingMethodsController < BaseController
    before_action :set_shipping_method, only: [:show, :edit, :update, :destroy]
    
    def index
      @shipping_methods = current_business.shipping_methods.order(name: :asc)
    end
    
    def show
    end
    
    def new
      @shipping_method = current_business.shipping_methods.new
    end
    
    def create
      @shipping_method = current_business.shipping_methods.new(shipping_method_params)
      
      if @shipping_method.save
        redirect_to business_manager_shipping_methods_path, notice: 'Shipping method was successfully created.'
      else
        render :new
      end
    end
    
    def edit
    end
    
    def update
      if @shipping_method.update(shipping_method_params)
        redirect_to business_manager_shipping_methods_path, notice: 'Shipping method was successfully updated.'
      else
        render :edit
      end
    end
    
    def destroy
      if @shipping_method.destroy
        redirect_to business_manager_shipping_methods_path, notice: 'Shipping method was successfully deleted.'
      else
        redirect_to business_manager_shipping_methods_path, alert: 'Cannot delete this shipping method as it is in use.'
      end
    end
    
    private
    
    def set_shipping_method
      @shipping_method = current_business.shipping_methods.find(params[:id])
    end
    
    def shipping_method_params
      params.require(:shipping_method).permit(:name, :cost, :active)
    end
  end
end 