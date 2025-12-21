# frozen_string_literal: true

class BusinessManager::ServiceJobFormsController < BusinessManager::BaseController
  before_action :set_service
  before_action :set_service_job_form, only: [:destroy]

  # POST /manage/services/:service_id/service_job_forms
  def create
    @service_job_form = @service.service_job_forms.new(service_job_form_params)

    if @service_job_form.save
      redirect_to edit_business_manager_service_path(@service, anchor: 'job-forms'),
                  notice: 'Job form assigned to service successfully.'
    else
      redirect_to edit_business_manager_service_path(@service, anchor: 'job-forms'),
                  alert: @service_job_form.errors.full_messages.join(', ')
    end
  end

  # DELETE /manage/services/:service_id/service_job_forms/:id
  def destroy
    @service_job_form.destroy
    redirect_to edit_business_manager_service_path(@service, anchor: 'job-forms'),
                notice: 'Job form removed from service.'
  end

  private

  def set_service
    @service = current_business.services.find(params[:service_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_services_path, alert: 'Service not found.'
    return
  end

  def set_service_job_form
    @service_job_form = @service.service_job_forms.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_business_manager_service_path(@service), alert: 'Job form assignment not found.'
    return
  end

  def service_job_form_params
    params.permit(:job_form_template_id, :timing, :required)
  end
end
