# frozen_string_literal: true

class BusinessManager::EstimatesController < BusinessManager::BaseController
  before_action :set_estimate, only: [:show, :edit, :update, :destroy, :send_to_customer, :download_pdf, :duplicate, :versions, :restore_version]
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
      redirect_to business_manager_estimate_path(@estimate), notice: 'Estimate created successfully.'
    else
      load_services_and_products
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
      :customer_notes, :internal_notes, :required_deposit,
      tenant_customer_attributes: [:id, :first_name, :last_name, :email, :phone, :address],
      estimate_items_attributes: [
        :id, :item_type, :service_id, :product_id, :product_variant_id,
        :description, :qty, :cost_rate, :tax_rate, :hours, :hourly_rate,
        :optional, :position, :_destroy
      ]
    )
  end
end
