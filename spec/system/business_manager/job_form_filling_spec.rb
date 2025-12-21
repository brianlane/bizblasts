# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Form Filling Workflow', type: :system do
  include_context 'setup business context'

  let(:service) { create(:service, business: business, name: 'Cleaning Service') }
  let(:booking) { create(:booking, business: business, service: service) }
  let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Cleaning Checklist') }

  before do
    driven_by(:rack_test)
    sign_in manager

    # Link the template to the service
    create(:service_job_form, service: service, job_form_template: template, timing: :before_service, required: true)
  end

  describe 'accessing job forms from booking page' do
    it 'shows booking details' do
      visit business_manager_booking_path(booking)

      # The booking page should show the booking information
      expect(page).to have_current_path(business_manager_booking_path(booking))
    end
  end

  describe 'filling out a job form' do
    it 'allows accessing the form filling page' do
      submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

      visit business_manager_job_form_submission_path(submission)

      expect(page).to have_content('Cleaning Checklist')
    end
  end

  describe 'reviewing completed forms' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'shows completed form on submission page' do
      visit business_manager_job_form_submission_path(submission)

      expect(page).to have_content('Cleaning Checklist')
      expect(page).to have_content('Submitted')
    end
  end

  describe 'form timing workflow' do
    it 'creates service job form with correct timing' do
      service_job_form = ServiceJobForm.find_by(service: service, job_form_template: template)

      expect(service_job_form.timing).to eq('before_service')
      expect(service_job_form.required).to be true
    end
  end
end
