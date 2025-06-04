module BusinessManager
  class TaxRatesController < BaseController
    before_action :set_tax_rate, only: [:show, :edit, :update, :destroy]
    
    def index
      @tax_rates = current_business.tax_rates.order(name: :asc)
    end
    
    def show
    end
    
    def new
      @tax_rate = current_business.tax_rates.new
    end
    
    def create
      @tax_rate = current_business.tax_rates.new(tax_rate_params)
      
      if @tax_rate.save
        redirect_to business_manager_tax_rates_path, notice: 'Tax rate was successfully created.'
      else
        render :new
      end
    end
    
    def edit
    end
    
    def update
      if @tax_rate.update(tax_rate_params)
        redirect_to business_manager_tax_rates_path, notice: 'Tax rate was successfully updated.'
      else
        render :edit
      end
    end
    
    def destroy
      if @tax_rate.destroy
        redirect_to business_manager_tax_rates_path, notice: 'Tax rate was successfully deleted.'
      else
        redirect_to business_manager_tax_rates_path, alert: 'Cannot delete this tax rate as it is in use.'
      end
    end
    
    private
    
    def set_tax_rate
      @tax_rate = current_business.tax_rates.find(params[:id])
    end
    
    def tax_rate_params
      permitted_params = params.require(:tax_rate).permit(:name, :rate, :region, :applies_to_shipping)
      
      # Convert rate from percentage format to decimal format
      if permitted_params[:rate].present?
        permitted_params[:rate] = permitted_params[:rate].to_f / 100
      end
      
      permitted_params
    end
  end
end 