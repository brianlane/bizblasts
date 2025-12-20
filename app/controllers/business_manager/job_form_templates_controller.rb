# frozen_string_literal: true

class BusinessManager::JobFormTemplatesController < BusinessManager::BaseController
  before_action :set_job_form_template, only: [:show, :edit, :update, :destroy, :toggle_active, :duplicate, :preview]

  # GET /manage/job_form_templates
  def index
    @job_form_templates = current_business.job_form_templates.ordered
                                          .includes(:services)

    if params[:active].present?
      @job_form_templates = @job_form_templates.where(active: params[:active] == 'true')
    end

    if params[:form_type].present?
      @job_form_templates = @job_form_templates.where(form_type: params[:form_type])
    end

    @job_form_templates = @job_form_templates.page(params[:page]) if @job_form_templates.respond_to?(:page)
  end

  # GET /manage/job_form_templates/:id
  def show
    @services_using = @job_form_template.services.positioned
    @submission_count = @job_form_template.job_form_submissions.count
  end

  # GET /manage/job_form_templates/new
  def new
    @job_form_template = current_business.job_form_templates.new
    @job_form_template.form_fields = []
  end

  # POST /manage/job_form_templates
  def create
    @job_form_template = current_business.job_form_templates.new(job_form_template_params)

    if @job_form_template.save
      redirect_to business_manager_job_form_template_path(@job_form_template), notice: 'Job form template was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /manage/job_form_templates/:id/edit
  def edit
  end

  # PATCH/PUT /manage/job_form_templates/:id
  def update
    if @job_form_template.update(job_form_template_params)
      redirect_to business_manager_job_form_template_path(@job_form_template), notice: 'Job form template was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /manage/job_form_templates/:id
  def destroy
    if @job_form_template.job_form_submissions.exists?
      redirect_to business_manager_job_form_templates_path, alert: 'Cannot delete a template that has submissions. Consider deactivating it instead.'
    else
      @job_form_template.destroy
      redirect_to business_manager_job_form_templates_path, notice: 'Job form template was successfully deleted.'
    end
  end

  # PATCH /manage/job_form_templates/:id/toggle_active
  def toggle_active
    @job_form_template.update(active: !@job_form_template.active)

    respond_to do |format|
      format.html { redirect_to business_manager_job_form_templates_path, notice: "Template #{@job_form_template.active? ? 'activated' : 'deactivated'} successfully." }
      format.json { render json: { active: @job_form_template.active } }
    end
  end

  # POST /manage/job_form_templates/:id/duplicate
  def duplicate
    new_template = @job_form_template.duplicate

    if new_template.save
      redirect_to edit_business_manager_job_form_template_path(new_template), notice: 'Template duplicated successfully. You can now edit it.'
    else
      redirect_to business_manager_job_form_templates_path, alert: 'Failed to duplicate template.'
    end
  end

  # GET /manage/job_form_templates/:id/preview
  def preview
    render layout: false
  end

  private

  def set_job_form_template
    @job_form_template = current_business.job_form_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_job_form_templates_path, alert: 'Template not found.'
  end

  def job_form_template_params
    params.require(:job_form_template).permit(
      :name,
      :description,
      :form_type,
      :active,
      :position,
      :form_fields_json
    ).tap do |whitelisted|
      # Handle the form_fields JSON structure from the form builder
      if params[:job_form_template][:form_fields_json].present?
        whitelisted[:form_fields] = parse_form_fields_json
        whitelisted.delete(:form_fields_json)
      end
    end
  end

  def parse_form_fields_json
    fields_json = params[:job_form_template][:form_fields_json]

    if fields_json.is_a?(String) && fields_json.present?
      JSON.parse(fields_json)
    else
      []
    end
  rescue JSON::ParserError
    []
  end
end
