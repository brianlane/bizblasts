# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Form Templates Management', type: :system do
  include_context 'setup business context'

  before do
    driven_by(:rack_test)
    sign_in manager
  end

  describe 'index page' do
    it 'displays list of job form templates' do
      template = create(:job_form_template, business: business, name: 'Pre-Service Checklist')

      visit business_manager_job_form_templates_path

      expect(page).to have_content('Pre-Service Checklist')
    end

    it 'shows active and inactive status' do
      active_template = create(:job_form_template, business: business, name: 'Active Form', active: true)
      inactive_template = create(:job_form_template, business: business, name: 'Inactive Form', active: false)

      visit business_manager_job_form_templates_path

      expect(page).to have_content('Active')
      expect(page).to have_content('Inactive')
    end
  end

  describe 'creating a new template' do
    it 'allows creating a checklist template' do
      visit new_business_manager_job_form_template_path

      fill_in 'Name', with: 'Pre-Service Checklist'
      fill_in 'Description', with: 'Checklist before starting service'
      select 'Checklist', from: 'Form type'

      click_button 'Create Template'

      expect(page).to have_content('Pre-Service Checklist')
      expect(page).to have_content('Job form template was successfully created')
    end

    it 'shows validation errors for invalid input' do
      visit new_business_manager_job_form_template_path

      click_button 'Create Template'

      expect(page).to have_content("Name can't be blank")
    end
  end

  describe 'editing a template' do
    let(:template) { create(:job_form_template, business: business, name: 'Original Name') }

    it 'allows updating template details' do
      visit edit_business_manager_job_form_template_path(template)

      fill_in 'Name', with: 'Updated Name'
      click_button 'Update Template'

      expect(page).to have_content('Updated Name')
    end
  end

  describe 'duplicating a template' do
    let!(:template) { create(:job_form_template, :with_fields, business: business, name: 'Template to Copy') }

    it 'creates a copy of the template' do
      visit business_manager_job_form_templates_path

      # Find the duplicate button (it's a button_to form, not a link)
      within("tr", text: 'Template to Copy') do
        find("button[title='Duplicate']").click
      end

      # The duplicate action redirects to the edit page of the copy
      expect(page).to have_content('Template duplicated successfully')
      expect(page).to have_content('Edit Template')
    end
  end

  describe 'toggling active status' do
    let!(:template) { create(:job_form_template, business: business, name: 'Toggle Test', active: true) }

    it 'toggles template active status' do
      visit business_manager_job_form_templates_path

      within("tr", text: 'Toggle Test') do
        find("button[title='Deactivate']").click
      end

      template.reload
      expect(template.active).to be false
    end
  end

  describe 'viewing a template' do
    let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Test Template') }

    it 'shows template details' do
      visit business_manager_job_form_template_path(template)

      expect(page).to have_content('Test Template')
      expect(page).to have_content('Checklist')
    end
  end

  describe 'previewing a template' do
    let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Preview Template') }

    it 'shows the template preview' do
      visit preview_business_manager_job_form_template_path(template)

      expect(page).to have_content('Preview Template')
    end
  end
end
