# frozen_string_literal: true

module BusinessManager
  class DocumentTemplatesController < BaseController
    before_action :set_template, only: [:edit, :update, :destroy]

    def index
      @templates = current_business.document_templates.order(:document_type, :name)
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

    private

    def set_template
      @template = current_business.document_templates.find(params[:id])
    end

    def template_params
      params.require(:document_template).permit(:name, :document_type, :body, :active)
    end
  end
end
