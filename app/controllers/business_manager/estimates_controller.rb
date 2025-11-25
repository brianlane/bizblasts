# frozen_string_literal: true

class BusinessManager::EstimatesController < BusinessManager::BaseController
  before_action :set_estimate, only: [:show, :edit, :update, :destroy, :send_to_customer]
  before_action :load_customers, only: [:new, :edit, :create, :update]

  def index
    @estimates = current_business.estimates.order(created_at: :desc)
  end

  def show; end

  def new
    @estimate = current_business.estimates.build
    @estimate.estimate_items.build
    @estimate.build_tenant_customer
  end

  def create
    # Handle customer selection logic similar to orders controller
    cp = estimate_params.to_h.with_indifferent_access
    
    # If selecting an existing customer, remove nested attributes
    if cp[:tenant_customer_id].present? && cp[:tenant_customer_id] != 'new'
      cp.delete(:tenant_customer_attributes)
    elsif cp[:tenant_customer_id] == 'new'
      # Remove placeholder and use nested attributes for new customer
      cp.delete(:tenant_customer_id)
    end
    
    @estimate = current_business.estimates.build(cp)
    
    if @estimate.save
      redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate created.'
    else
      # Rebuild associations if removed during validation to preserve form state
      @estimate.estimate_items.build if @estimate.estimate_items.empty?
      @estimate.build_tenant_customer unless @estimate.tenant_customer
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @estimate.estimate_items.build if @estimate.estimate_items.empty?
    @estimate.build_tenant_customer unless @estimate.tenant_customer
  end

  def update
    # Handle customer selection logic similar to orders controller
    cp = estimate_params.to_h.with_indifferent_access
    
    # If selecting an existing customer, remove nested attributes
    if cp[:tenant_customer_id].present? && cp[:tenant_customer_id] != 'new'
      cp.delete(:tenant_customer_attributes)
    elsif cp[:tenant_customer_id] == 'new'
      # Remove placeholder and use nested attributes for new customer
      cp.delete(:tenant_customer_id)
    end
    
    if @estimate.update(cp)
      redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate updated.'
    else
      # Rebuild associations if removed during validation to preserve form state
      @estimate.estimate_items.build if @estimate.estimate_items.empty?
      @estimate.build_tenant_customer unless @estimate.tenant_customer
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @estimate.destroy
    redirect_to business_manager_estimates_path, notice: 'Estimate deleted.'
  end

  def send_to_customer
    if @estimate.update(status: :sent, sent_at: Time.current)
      EstimateMailer.send_estimate(@estimate).deliver_later
      redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate sent to customer.'
    else
      redirect_to business_manager_estimate_path(@estimate), alert: 'Could not send estimate.'
    end
  end

  private

  def set_estimate
    @estimate = current_business.estimates.find(params[:id])
  end

  def load_customers
    @customers = current_business.tenant_customers.order(:first_name, :last_name)
  end

  def estimate_params
    params.require(:estimate).permit(
      :tenant_customer_id, :proposed_start_time, :first_name, :last_name, :email,
      :phone, :address, :city, :state, :zip, :customer_notes, :internal_notes,
      :required_deposit,
      :total,
      tenant_customer_attributes: [:id, :first_name, :last_name, :email, :phone, :address],
      estimate_items_attributes: [:id, :service_id, :description, :qty, :cost_rate, :tax_rate, :_destroy]
    )
  end
end 