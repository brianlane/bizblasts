# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::JobFormTemplates', type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    host! "#{business.subdomain}.lvh.me"
    sign_in user
    ActsAsTenant.current_tenant = business
  end

  describe 'GET /manage/job_form_templates' do
    it 'returns a successful response' do
      get business_manager_job_form_templates_path

      expect(response).to be_successful
    end

    it 'displays job form templates for the business' do
      template = create(:job_form_template, business: business, name: 'Test Template')

      get business_manager_job_form_templates_path

      expect(response.body).to include('Test Template')
    end
  end

  describe 'GET /manage/job_form_templates/:id' do
    let(:template) { create(:job_form_template, :with_fields, business: business) }

    it 'returns a successful response' do
      get business_manager_job_form_template_path(template)

      expect(response).to be_successful
    end

    it 'displays the template details' do
      get business_manager_job_form_template_path(template)

      expect(response.body).to include(template.name)
    end
  end

  describe 'GET /manage/job_form_templates/new' do
    it 'returns a successful response' do
      get new_business_manager_job_form_template_path

      expect(response).to be_successful
    end
  end

  describe 'POST /manage/job_form_templates' do
    let(:valid_params) do
      {
        job_form_template: {
          name: 'New Template',
          description: 'Template description',
          form_type: 'checklist',
          active: true,
          form_fields_json: [
            { id: SecureRandom.uuid, type: 'checkbox', label: 'Item Checked', required: true }
          ].to_json
        }
      }
    end

    it 'creates a new job form template' do
      expect {
        post business_manager_job_form_templates_path, params: valid_params
      }.to change(JobFormTemplate, :count).by(1)
    end

    it 'redirects to the template page' do
      post business_manager_job_form_templates_path, params: valid_params

      expect(response).to redirect_to(business_manager_job_form_template_path(JobFormTemplate.last))
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          job_form_template: {
            name: '', # Required field
            form_type: 'checklist'
          }
        }
      end

      it 'does not create a template' do
        expect {
          post business_manager_job_form_templates_path, params: invalid_params
        }.not_to change(JobFormTemplate, :count)
      end

      it 'renders the new form' do
        post business_manager_job_form_templates_path, params: invalid_params

        expect(response).to be_unprocessable
      end
    end
  end

  describe 'GET /manage/job_form_templates/:id/edit' do
    let(:template) { create(:job_form_template, business: business) }

    it 'returns a successful response' do
      get edit_business_manager_job_form_template_path(template)

      expect(response).to be_successful
    end
  end

  describe 'PATCH /manage/job_form_templates/:id' do
    let(:template) { create(:job_form_template, business: business) }

    it 'updates the template' do
      patch business_manager_job_form_template_path(template), params: {
        job_form_template: { name: 'Updated Name' }
      }

      template.reload
      expect(template.name).to eq('Updated Name')
    end

    it 'redirects to the template page' do
      patch business_manager_job_form_template_path(template), params: {
        job_form_template: { name: 'Updated Name' }
      }

      expect(response).to redirect_to(business_manager_job_form_template_path(template))
    end
  end

  describe 'DELETE /manage/job_form_templates/:id' do
    let!(:template) { create(:job_form_template, business: business) }

    it 'deletes the template' do
      expect {
        delete business_manager_job_form_template_path(template)
      }.to change(JobFormTemplate, :count).by(-1)
    end

    it 'redirects to the index' do
      delete business_manager_job_form_template_path(template)

      expect(response).to redirect_to(business_manager_job_form_templates_path)
    end

    context 'when template has submissions' do
      before do
        booking = create(:booking, business: business)
        create(:job_form_submission, business: business, booking: booking, job_form_template: template)
      end

      it 'does not delete the template' do
        expect {
          delete business_manager_job_form_template_path(template)
        }.not_to change(JobFormTemplate, :count)
      end
    end
  end

  describe 'PATCH /manage/job_form_templates/:id/toggle_active' do
    let(:template) { create(:job_form_template, :active_with_fields, business: business) }

    it 'toggles the active status' do
      patch toggle_active_business_manager_job_form_template_path(template)

      template.reload
      expect(template.active).to be false
    end

    it 'redirects back' do
      patch toggle_active_business_manager_job_form_template_path(template)

      expect(response).to redirect_to(business_manager_job_form_templates_path)
    end
  end

  describe 'POST /manage/job_form_templates/:id/duplicate' do
    let!(:template) { create(:job_form_template, :with_fields, business: business, name: 'Original') }

    it 'creates a duplicate template' do
      expect {
        post duplicate_business_manager_job_form_template_path(template)
      }.to change(JobFormTemplate, :count).by(1)
    end

    it 'redirects to the edit page of the new template' do
      post duplicate_business_manager_job_form_template_path(template)

      new_template = JobFormTemplate.last
      expect(response).to redirect_to(edit_business_manager_job_form_template_path(new_template))
    end

    it 'creates a copy with the correct name' do
      post duplicate_business_manager_job_form_template_path(template)

      new_template = JobFormTemplate.last
      expect(new_template.name).to eq('Original (Copy)')
    end
  end

  describe 'GET /manage/job_form_templates/:id/preview' do
    let(:template) { create(:job_form_template, :with_fields, business: business) }

    it 'returns a successful response' do
      get preview_business_manager_job_form_template_path(template)

      expect(response).to be_successful
    end
  end

  describe 'authorization' do
    let(:other_business) { create(:business) }
    let(:other_template) do
      ActsAsTenant.without_tenant do
        create(:job_form_template, business: other_business)
      end
    end

    it 'redirects when accessing templates from other businesses' do
      get business_manager_job_form_template_path(other_template)

      expect(response).to redirect_to(business_manager_job_form_templates_path)
    end
  end
end
