# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Form Templates Management', type: :system do
  let(:business) { create(:business, :with_owner) }
  let(:user) { business.users.find_by(role: :manager) || create(:user, :manager, business: business) }

  before do
    driven_by(:rack_test)
    sign_in user
  end

  describe 'index page' do
    it 'displays list of job form templates' do
      template = create(:job_form_template, business: business, name: 'Pre-Service Checklist')

      visit business_manager_job_form_templates_path

      expect(page).to have_content('Pre-Service Checklist')
    end

    it 'shows active and inactive status' do
      active_template = create(:job_form_template, business: business, name: 'Active Template', active: true)
      inactive_template = create(:job_form_template, business: business, name: 'Inactive Template', active: false)

      visit business_manager_job_form_templates_path

      expect(page).to have_content('Active Template')
      expect(page).to have_content('Inactive Template')
    end
  end

  describe 'creating a new template' do
    it 'allows creating a checklist template' do
      visit new_business_manager_job_form_template_path

      fill_in 'Name', with: 'Equipment Check'
      fill_in 'Description', with: 'Verify all equipment before service'
      select 'Checklist', from: 'Form type'
      check 'Active'

      click_button 'Create'

      expect(page).to have_content('Equipment Check')
    end

    it 'shows validation errors for invalid input' do
      visit new_business_manager_job_form_template_path

      click_button 'Create'

      expect(page).to have_content("can't be blank")
    end
  end

  describe 'editing a template' do
    let(:template) { create(:job_form_template, business: business, name: 'Original Name') }

    it 'allows updating template details' do
      visit edit_business_manager_job_form_template_path(template)

      fill_in 'Name', with: 'Updated Template Name'
      click_button 'Update'

      expect(page).to have_content('Updated Template Name')
    end
  end

  describe 'duplicating a template' do
    let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Template to Copy') }

    it 'creates a copy of the template' do
      visit business_manager_job_form_templates_path

      # Find and click the duplicate action
      within("tr", text: 'Template to Copy') do
        click_link 'Duplicate'
      end

      expect(page).to have_content('Template to Copy (Copy)')
    end
  end

  describe 'toggling active status' do
    let!(:template) { create(:job_form_template, business: business, name: 'Toggle Test', active: true) }

    it 'toggles template active status' do
      visit business_manager_job_form_templates_path

      within("tr", text: 'Toggle Test') do
        click_button 'Deactivate'
      end

      template.reload
      expect(template.active).to be false
    end
  end

  describe 'deleting a template' do
    let!(:template) { create(:job_form_template, business: business, name: 'Template to Delete') }

    it 'removes the template' do
      visit business_manager_job_form_templates_path

      accept_confirm do
        within("tr", text: 'Template to Delete') do
          click_link 'Delete'
        end
      end

      expect(page).not_to have_content('Template to Delete')
    end

    context 'when template has submissions' do
      let(:service) { create(:service, business: business) }
      let(:booking) { create(:booking, business: business, service: service) }

      before do
        create(:job_form_submission, business: business, booking: booking, job_form_template: template)
      end

      it 'prevents deletion' do
        visit business_manager_job_form_templates_path

        within("tr", text: 'Template to Delete') do
          expect(page).not_to have_link('Delete')
        end
      end
    end
  end

  describe 'previewing a template' do
    let(:template) { create(:job_form_template, :with_fields, business: business) }

    it 'shows the template preview' do
      visit preview_business_manager_job_form_template_path(template)

      expect(page).to have_content(template.name)
      expect(page).to have_content('Equipment checked') # from :with_fields trait
    end
  end
end
