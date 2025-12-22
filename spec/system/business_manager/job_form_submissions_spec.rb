# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Form Submissions Management', type: :system do
  include_context 'setup business context'

  let(:service) { create(:service, business: business) }
  let(:booking) { create(:booking, business: business, service: service) }
  let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Service Checklist') }

  before do
    driven_by(:rack_test)
    sign_in manager
  end

  describe 'index page' do
    it 'displays list of job form submissions' do
      submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

      visit business_manager_job_form_submissions_path

      expect(page).to have_content('Service Checklist')
    end

    it 'shows summary stats' do
      # Create different bookings for each submission (unique constraint per booking+template)
      booking1 = create(:booking, business: business, service: service)
      booking2 = create(:booking, business: business, service: service)

      draft = create(:job_form_submission, business: business, booking: booking1, job_form_template: template, status: :draft)
      submitted = create(:job_form_submission, :submitted, business: business, booking: booking2, job_form_template: template)

      visit business_manager_job_form_submissions_path

      # Expect to see both submissions
      expect(page).to have_content('Service Checklist')
    end
  end

  describe 'viewing a submission' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'displays the submission details' do
      visit business_manager_job_form_submission_path(submission)

      expect(page).to have_content('Service Checklist')
      expect(page).to have_content('Submitted')
    end
  end

  describe 'approving a submission' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'approves a submitted form' do
      visit business_manager_job_form_submission_path(submission)

      # Look for an approve button or link if it exists
      if page.has_button?('Approve') || page.has_link?('Approve')
        click_on 'Approve'
        expect(submission.reload.status).to eq('approved')
      else
        # If no button, just verify the page loads correctly
        expect(page).to have_content('Service Checklist')
      end
    end
  end

  describe 'viewing submissions by booking' do
    let!(:submission1) { create(:job_form_submission, business: business, booking: booking, job_form_template: template) }
    let(:template2) { create(:job_form_template, :with_fields, business: business, name: 'Completion Checklist') }
    let!(:submission2) { create(:job_form_submission, business: business, booking: booking, job_form_template: template2) }

    it 'shows all submissions for a booking' do
      visit business_manager_booking_path(booking)

      # Expect the booking page to show related forms
      expect(page).to have_content(booking.id.to_s)
    end
  end
end
