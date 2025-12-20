# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Form Filling Workflow', type: :system do
  let(:business) { create(:business, :with_owner) }
  let(:user) { business.users.find_by(role: :manager) || create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business, name: 'Cleaning Service') }
  let(:booking) { create(:booking, business: business, service: service) }
  let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Cleaning Checklist') }

  before do
    driven_by(:rack_test)
    sign_in user

    # Link the template to the service
    create(:service_job_form, service: service, job_form_template: template, timing: :before_service, required: true)
  end

  describe 'accessing job forms from booking page' do
    it 'shows pending job forms section' do
      visit business_manager_booking_path(booking)

      expect(page).to have_content('Cleaning Checklist')
      expect(page).to have_link('Fill Form')
    end

    it 'shows form timing' do
      visit business_manager_booking_path(booking)

      expect(page).to have_content('Before')
    end
  end

  describe 'filling out a job form' do
    it 'allows completing required fields' do
      visit business_manager_booking_path(booking)
      click_link 'Fill Form'

      # Fill in the form fields (based on :with_fields trait)
      check 'Equipment checked'
      fill_in 'Notes', with: 'All equipment verified and working'
      select 'Excellent', from: 'Condition'

      click_button 'Submit'

      expect(page).to have_content('submitted')
    end

    it 'validates required fields' do
      visit business_manager_booking_path(booking)
      click_link 'Fill Form'

      # Try to submit without completing required fields
      click_button 'Submit'

      expect(page).to have_content('required')
    end

    it 'saves progress as draft' do
      visit business_manager_booking_path(booking)
      click_link 'Fill Form'

      check 'Equipment checked'
      click_button 'Save Draft'

      expect(page).to have_content('saved')
    end
  end

  describe 'reviewing completed forms' do
    let!(:submission) do
      sub = create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template)
      template.form_fields.each do |field|
        sub.set_response(field['id'], 'Completed value')
      end
      sub.save!
      sub
    end

    it 'shows completed form on booking page' do
      visit business_manager_booking_path(booking)

      expect(page).to have_content('Cleaning Checklist')
      expect(page).to have_content('Submitted')
    end

    it 'allows viewing form details' do
      visit business_manager_booking_path(booking)
      click_link 'View'

      expect(page).to have_content('Completed value')
    end

    it 'shows form completion percentage' do
      visit business_manager_booking_path(booking)

      expect(page).to have_content('100%')
    end
  end

  describe 'form timing workflow' do
    let(:before_template) { create(:job_form_template, business: business, name: 'Pre-Service Check') }
    let(:during_template) { create(:job_form_template, business: business, name: 'During Service Notes') }
    let(:after_template) { create(:job_form_template, business: business, name: 'Completion Report') }

    before do
      create(:service_job_form, service: service, job_form_template: before_template, timing: :before_service)
      create(:service_job_form, service: service, job_form_template: during_template, timing: :during_service)
      create(:service_job_form, service: service, job_form_template: after_template, timing: :after_service)
    end

    it 'groups forms by timing' do
      visit business_manager_booking_path(booking)

      expect(page).to have_content('Before Service')
      expect(page).to have_content('During Service')
      expect(page).to have_content('After Service')
    end
  end

  describe 'revision workflow' do
    let!(:submission) do
      create(:job_form_submission, business: business, booking: booking, job_form_template: template, status: :requires_revision, notes: 'Add more details')
    end

    it 'shows revision request on booking page' do
      visit business_manager_booking_path(booking)

      expect(page).to have_content('Requires Revision')
    end

    it 'allows revising the form' do
      visit business_manager_booking_path(booking)
      click_link 'Revise'

      fill_in 'Notes', with: 'Updated notes with more detail'
      click_button 'Submit'

      expect(page).to have_content('submitted')
    end
  end
end
