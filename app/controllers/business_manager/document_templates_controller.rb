# frozen_string_literal: true

module BusinessManager
  class DocumentTemplatesController < BaseController
    before_action :set_template, only: [:edit, :update, :destroy, :send_document, :create_and_send]

    def index
      @document_type_filters = [['All templates', 'all']] + DocumentTemplate::DOCUMENT_TYPES
      scope = current_business.document_templates.order(:document_type, :name)
      @latest_version_map = current_business.document_templates.group(:document_type).maximum(:version)
      @selected_document_type = params[:document_type].presence || 'all'

      if @selected_document_type != 'all'
        scope = scope.where(document_type: @selected_document_type)
      end

      @templates = scope
    end

    def new
      @template = current_business.document_templates.new(document_type: params[:document_type])
    end

    def create
      @template = current_business.document_templates.new(template_params)
      if @template.save
        redirect_to business_manager_document_templates_path, notice: 'Template created successfully.'
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit; end

    def update
      if @template.update(template_params)
        redirect_to business_manager_document_templates_path, notice: 'Template updated successfully.'
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @template.destroy
      redirect_to business_manager_document_templates_path, notice: 'Template deleted.'
    end

    # GET - Show form to send a standalone document
    def send_document
      @customers = current_business.tenant_customers.order(:first_name, :last_name)
      @client_document = current_business.client_documents.new(
        document_template: @template,
        document_type: @template.document_type,
        title: @template.name,
        body: @template.body,
        signature_required: true,
        payment_required: false,
        deposit_amount: 0
      )
    end

    # POST - Create and send a standalone document to a customer
    def create_and_send
      customer = nil
      customer_email = nil
      customer_name = nil

      # Handle existing customer or new email
      if params[:tenant_customer_id].present?
        customer = current_business.tenant_customers.find_by(id: params[:tenant_customer_id])
        if customer.nil?
          redirect_to send_document_business_manager_document_template_path(@template), alert: 'Customer not found.'
          return
        end
        customer_email = customer.email
        customer_name = customer.full_name
      elsif params[:customer_email].present?
        customer_email = params[:customer_email]
        customer_name = params[:customer_name].presence || customer_email.split('@').first
        # Try to find or create customer
        customer = current_business.tenant_customers.find_or_create_by(email: customer_email) do |c|
          c.first_name = customer_name.split.first
          c.last_name = customer_name.split[1..].join(' ').presence
        end
      else
        redirect_to send_document_business_manager_document_template_path(@template), alert: 'Please select a customer or enter an email address.'
        return
      end

      # Create the client document
      @client_document = current_business.client_documents.new(
        document_template: @template,
        tenant_customer: customer,
        document_type: 'standalone',
        title: params[:title].presence || @template.name,
        body: @template.body,
        status: 'sent',
        sent_at: Time.current,
        signature_required: params[:signature_required] == '1',
        payment_required: params[:payment_required] == '1',
        deposit_amount: params[:deposit_amount].to_f
      )

      if @client_document.save
        # Send the email
        ClientDocumentMailer.send_document(@client_document, customer_email, customer_name).deliver_later
        redirect_to business_manager_document_templates_path, notice: "Document sent to #{customer_email} successfully."
      else
        @customers = current_business.tenant_customers.order(:first_name, :last_name)
        flash.now[:alert] = 'Failed to create document.'
        render :send_document, status: :unprocessable_content
      end
    end

    private

    def set_template
      @template = current_business.document_templates.find(params[:id])
    end

    def template_params
      params.require(:document_template).permit(:name, :document_type, :body, :active)
    end
  end
end
