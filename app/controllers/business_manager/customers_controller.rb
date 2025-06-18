# frozen_string_literal: true

class BusinessManager::CustomersController < BusinessManager::BaseController
  before_action :set_customer, only: [:show, :edit, :update, :destroy]

  # GET /manage/customers
  def index
    @customers = @current_business.tenant_customers.order(:first_name, :last_name).page(params[:page]).per(10)
    authorize TenantCustomer
  end

  # GET /manage/customers/:id
  def show
    authorize @customer
  end

  # GET /manage/customers/new
  def new
    @customer = @current_business.tenant_customers.new
    authorize @customer
  end

  # POST /manage/customers
  def create
    @customer = @current_business.tenant_customers.new(customer_params)
    authorize @customer
    @customer.skip_notification_email = true

    if @customer.save
      redirect_to business_manager_customers_path, notice: 'Customer was successfully created.'
    else
      render :new
    end
  end

  # GET /manage/customers/:id/edit
  def edit
    authorize @customer
  end

  # PATCH/PUT /manage/customers/:id
  def update
    authorize @customer
    if @customer.update(customer_params)
      redirect_to business_manager_customer_path(@customer), notice: 'Customer was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /manage/customers/:id
  def destroy
    authorize @customer
    if @customer.destroy
      redirect_to business_manager_customers_path, notice: 'Customer was successfully deleted.'
    else
      redirect_to business_manager_customers_path, alert: @customer.errors.full_messages.to_sentence
    end
  end

  private

  def set_customer
    @customer = @current_business.tenant_customers.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_customers_path, alert: 'Customer not found.'
  end

  def customer_params
    params.require(:tenant_customer).permit(:first_name, :last_name, :email, :phone, :address, :notes, :active)
  end
end 