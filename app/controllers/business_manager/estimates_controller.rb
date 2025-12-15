# frozen_string_literal: true

class BusinessManager::EstimatesController < BusinessManager::BaseController
  before_action :set_estimate, only: [:show, :edit, :update, :destroy, :send_to_customer, :resend_to_customer, :download_pdf, :duplicate, :versions, :restore_version]
  before_action :load_customers, only: [:new, :edit, :create, :update]
  before_action :load_services_and_products, only: [:new, :edit, :create, :update]

  def index
    @estimates = current_business.estimates
      .includes(:tenant_customer, :estimate_items)
      .order(created_at: :desc)
      .page(params[:page])
      .per(25)

    # Filter by status if provided
    @estimates = @estimates.where(status: params[:status]) if params[:status].present?
  end

  def show
    @versions = @estimate.estimate_versions.recent if @estimate.respond_to?(:estimate_versions)
  end

  def new
    @estimate = current_business.estimates.build
    @estimate.estimate_items.build
    @estimate.build_tenant_customer
  end

  def create
    # Extract save-for-future data BEFORE building estimate
    save_data = extract_save_for_future_data(params)

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

    ActiveRecord::Base.transaction do
      if @estimate.save
        process_save_for_future(save_data) if save_data.any?
        redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate created successfully.'
      else
        load_services_and_products
        # Rebuild associations if removed during validation to preserve form state
        @estimate.estimate_items.build if @estimate.estimate_items.empty?
        @estimate.build_tenant_customer unless @estimate.tenant_customer
        render :new, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    load_services_and_products
    @estimate.errors.add(:base, "Failed to save items for future use: #{e.message}")
    render :new, status: :unprocessable_entity
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
      redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate updated successfully.'
    else
      load_services_and_products
      # Rebuild associations if removed during validation to preserve form state
      @estimate.estimate_items.build if @estimate.estimate_items.empty?
      @estimate.build_tenant_customer unless @estimate.tenant_customer
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @estimate.destroy
    redirect_to business_manager_estimates_path, notice: 'Estimate deleted successfully.'
  end

  def send_to_customer
    # Generate PDF before sending
    EstimatePdfGenerator.new(@estimate).generate unless @estimate.pdf.attached?

    if @estimate.update(status: :sent, sent_at: Time.current)
      EstimateMailer.send_estimate(@estimate).deliver_later
      redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate sent to customer successfully.'
    else
      redirect_to business_manager_estimate_path(@estimate), alert: 'Could not send estimate.'
    end
  end

  def resend_to_customer
    # Regenerate PDF to ensure it's up to date
    EstimatePdfGenerator.new(@estimate).generate

    # Send email without changing status (keep current status like 'sent' or 'viewed')
    EstimateMailer.send_estimate(@estimate).deliver_later
    redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate resent to customer successfully.'
  end

  def download_pdf
    # Generate PDF if not already generated
    EstimatePdfGenerator.new(@estimate).generate unless @estimate.pdf.attached?

    if @estimate.pdf.attached?
      redirect_to rails_blob_path(@estimate.pdf, disposition: "attachment")
    else
      redirect_to business_manager_estimate_path(@estimate), alert: 'Could not generate PDF.'
    end
  end

  def duplicate
    new_estimate = @estimate.dup
    new_estimate.status = :draft
    new_estimate.sent_at = nil
    new_estimate.viewed_at = nil
    new_estimate.approved_at = nil
    new_estimate.declined_at = nil
    new_estimate.signed_at = nil
    new_estimate.signature_data = nil
    new_estimate.signature_name = nil
    new_estimate.estimate_number = nil # Will be regenerated
    new_estimate.token = nil # Will be regenerated
    new_estimate.current_version = 1
    new_estimate.total_versions = 1
    new_estimate.checkout_session_id = nil
    new_estimate.payment_intent_id = nil
    new_estimate.pdf_generated_at = nil
    new_estimate.deposit_paid_at = nil

    if new_estimate.save
      # Duplicate items
      @estimate.estimate_items.each do |item|
        new_item = item.dup
        new_item.estimate = new_estimate
        new_item.customer_selected = true
        new_item.customer_declined = false
        new_item.save
      end

      # Recalculate totals after adding all items
      new_estimate.recalculate_totals!

      redirect_to edit_business_manager_estimate_path(new_estimate),
        notice: 'Estimate duplicated. Make any necessary changes and save.'
    else
      redirect_to business_manager_estimate_path(@estimate),
        alert: 'Failed to duplicate estimate.'
    end
  end

  # GET /manage/estimates/:id/versions
  # Displays version history for an estimate
  def versions
    @versions = @estimate.estimate_versions.order(version_number: :desc)

    respond_to do |format|
      format.html
      format.json { render json: @versions.map { |v| version_json(v) } }
    end
  end

  # PATCH /manage/estimates/:id/restore_version/:version_id
  # Restores an estimate to a previous version
  def restore_version
    @version = @estimate.estimate_versions.find(params[:version_id])

    # Only allow restore if estimate is in a modifiable state
    unless @estimate.draft? || @estimate.sent? || @estimate.viewed?
      redirect_to versions_business_manager_estimate_path(@estimate),
        alert: 'Cannot restore version for estimates that are approved, declined, or cancelled.'
      return
    end

    if EstimateVersioningService.restore_version(@version)
      # Regenerate PDF after restore
      @estimate.pdf.purge if @estimate.pdf.attached?

      redirect_to business_manager_estimate_path(@estimate),
        notice: "Estimate restored to version #{@version.version_number}."
    else
      redirect_to versions_business_manager_estimate_path(@estimate),
        alert: 'Failed to restore version. Please try again.'
    end
  end

  private

  # Format version data for JSON response
  def version_json(version)
    {
      id: version.id,
      version_number: version.version_number,
      created_at: version.created_at.iso8601,
      change_notes: version.change_notes,
      snapshot_summary: {
        total: version.snapshot.dig('version_metadata', 'total'),
        item_count: version.snapshot.dig('version_metadata', 'item_count'),
        has_signature: version.snapshot.dig('version_metadata', 'has_signature')
      }
    }
  end

  def set_estimate
    @estimate = current_business.estimates.find(params[:id])
  end

  def load_customers
    @customers = current_business.tenant_customers.order(:first_name, :last_name)
  end

  def load_services_and_products
    @services = current_business.services.order(:name)
    @products = current_business.products.order(:name) if current_business.respond_to?(:products)
    @products ||= []
  end

  def estimate_params
    params.require(:estimate).permit(
      :tenant_customer_id, :proposed_start_time, :proposed_end_time,
      :first_name, :last_name, :email, :phone, :address, :city, :state, :zip,
      :customer_notes, :internal_notes, :required_deposit, :valid_for_days,
      tenant_customer_attributes: [:id, :first_name, :last_name, :email, :phone, :address],
      estimate_items_attributes: [
        :id, :item_type, :service_id, :product_id, :product_variant_id,
        :description, :qty, :cost_rate, :tax_rate, :hours, :hourly_rate,
        :optional, :position, :_destroy,
        :save_as_service, :service_type, :service_name,
        :save_as_product, :product_type, :product_name
      ]
    )
  end

  # Extract save-for-future data from params for labor→service and part→product
  def extract_save_for_future_data(params)
    return [] unless params[:estimate] && params[:estimate][:estimate_items_attributes]

    save_data = []
    params[:estimate][:estimate_items_attributes].values.each_with_index do |item_attrs, row_order|
      # Labor → Service
      if item_attrs[:save_as_service] == '1' && item_attrs[:item_type] == 'labor'
        save_data << {
          row_order: row_order,
          type: :service,
          service_type: item_attrs[:service_type],
          name: item_attrs[:service_name],
          description: item_attrs[:description],
          item_type: 'labor'
        }
      end

      # Part → Product
      if item_attrs[:save_as_product] == '1' && item_attrs[:item_type] == 'part'
        save_data << {
          row_order: row_order,
          type: :product,
          product_type: item_attrs[:product_type],
          name: item_attrs[:product_name],
          description: item_attrs[:description],
          item_type: 'part'
        }
      end
    end

    save_data
  end

  # Process all save-for-future requests after estimate is created
  def process_save_for_future(save_data)
    save_data.each do |data|
      item = find_estimate_item_by_data(data)
      next unless item

      if data[:type] == :service
        create_service_from_labor(item, data)
      elsif data[:type] == :product
        create_product_from_part(item, data)
      end
    end
  end

  # Find estimate item by description and type (more reliable than position)
  def find_estimate_item_by_data(data)
    ordered_items = @estimate.estimate_items.order(:position)
    item = ordered_items[data[:row_order].to_i] if data[:row_order]
    return item if item

    # Fallback to matching by description/item type if ordering fails
    ordered_items.find_by(
      description: data[:description],
      item_type: data[:item_type]
    )
  end

  # Create service from labor item and convert item type
  def create_service_from_labor(item, data)
    # Calculate duration and price from hours and hourly_rate
    hours = item.hours.to_f
    hourly_rate = item.hourly_rate.to_f
    duration = (hours * 60).ceil # minutes, rounded up
    price = hours * hourly_rate

    service = current_business.services.create!(
      name: data[:name],
      service_type: data[:service_type],
      duration: duration,
      price: price,
      description: item.description,
      created_from_estimate_id: @estimate.id
    )

    # Convert EstimateItem to service type
    item.update!(
      item_type: :service,
      service_id: service.id,
      qty: 1,
      cost_rate: price
    )
  end

  # Create product from part item and convert item type
  def create_product_from_part(item, data)
    # Use cost_rate as the product price
    price = item.cost_rate.to_f

    product = current_business.products.create!(
      name: data[:name],
      product_type: data[:product_type],
      price: price,
      description: item.description,
      stock_quantity: 0
    )

    # Convert EstimateItem to product type
    item.update!(
      item_type: :product,
      product_id: product.id,
      cost_rate: price
    )
  end
end
