# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::ServiceJobForms', type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business) }
  let(:template) { create(:job_form_template, business: business) }

  before do
    sign_in user
    ActsAsTenant.current_tenant = business
  end

  describe 'POST /manage/services/:service_id/service_job_forms' do
    let(:valid_params) do
      {
        job_form_template_id: template.id,
        timing: 'before_service',
        required: true
      }
    end

    it 'creates a new service job form assignment' do
      expect {
        post business_manager_service_service_job_forms_path(service), params: valid_params
      }.to change(ServiceJobForm, :count).by(1)
    end

    it 'redirects to the service edit page with anchor' do
      post business_manager_service_service_job_forms_path(service), params: valid_params

      expect(response).to redirect_to(edit_business_manager_service_path(service, anchor: 'job-forms'))
    end

    it 'assigns the form template to the service' do
      post business_manager_service_service_job_forms_path(service), params: valid_params

      service_job_form = ServiceJobForm.last
      expect(service_job_form.service).to eq(service)
      expect(service_job_form.job_form_template).to eq(template)
      expect(service_job_form.timing).to eq('before_service')
      expect(service_job_form.required).to be true
    end

    context 'with different timing options' do
      %w[before_service during_service after_service].each do |timing|
        it "creates with #{timing} timing" do
          post business_manager_service_service_job_forms_path(service), params: valid_params.merge(timing: timing)

          expect(ServiceJobForm.last.timing).to eq(timing)
        end
      end
    end

    context 'with duplicate assignment' do
      before { create(:service_job_form, service: service, job_form_template: template) }

      it 'does not create a duplicate' do
        expect {
          post business_manager_service_service_job_forms_path(service), params: valid_params
        }.not_to change(ServiceJobForm, :count)
      end

      it 'redirects with error message' do
        post business_manager_service_service_job_forms_path(service), params: valid_params

        expect(response).to redirect_to(edit_business_manager_service_path(service, anchor: 'job-forms'))
        expect(flash[:alert]).to be_present
      end
    end

    context 'with template from different business' do
      let(:other_business) { create(:business) }
      let(:other_template) { create(:job_form_template, business: other_business) }

      it 'does not create the assignment' do
        expect {
          post business_manager_service_service_job_forms_path(service), params: {
            job_form_template_id: other_template.id,
            timing: 'before_service'
          }
        }.not_to change(ServiceJobForm, :count)
      end
    end
  end

  describe 'DELETE /manage/services/:service_id/service_job_forms/:id' do
    let!(:service_job_form) { create(:service_job_form, service: service, job_form_template: template) }

    it 'deletes the service job form assignment' do
      expect {
        delete business_manager_service_service_job_form_path(service, service_job_form)
      }.to change(ServiceJobForm, :count).by(-1)
    end

    it 'redirects to the service edit page with anchor' do
      delete business_manager_service_service_job_form_path(service, service_job_form)

      expect(response).to redirect_to(edit_business_manager_service_path(service, anchor: 'job-forms'))
    end
  end

  describe 'authorization' do
    let(:other_business) { create(:business) }
    let(:other_service) { create(:service, business: other_business) }

    it 'redirects when accessing services from other businesses' do
      expect {
        post business_manager_service_service_job_forms_path(other_service), params: {
          job_form_template_id: template.id,
          timing: 'before_service'
        }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
