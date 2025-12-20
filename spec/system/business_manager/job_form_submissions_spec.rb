# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Form Submissions Management', type: :system do
  let(:business) { create(:business, :with_owner) }
  let(:user) { business.users.find_by(role: :manager) || create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business) }
  let(:booking) { create(:booking, business: business, service: service) }
  let(:template) { create(:job_form_template, :with_fields, business: business, name: 'Service Checklist') }

  before do
    driven_by(:rack_test)
    sign_in user
  end

  describe 'index page' do
    it 'displays list of job form submissions' do
      submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

      visit business_manager_job_form_submissions_path

      expect(page).to have_content('Service Checklist')
    end

    it 'shows summary stats' do
      create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template)
      create(:job_form_submission, :approved, business: business, booking: booking, job_form_template: create(:job_form_template, business: business))

      visit business_manager_job_form_submissions_path

      expect(page).to have_content('Pending')
      expect(page).to have_content('Completed')
    end
  end

  describe 'filtering submissions' do
    let!(:draft_submission) { create(:job_form_submission, business: business, booking: booking, job_form_template: template, status: :draft) }
    let!(:submitted_submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: create(:job_form_template, business: business, name: 'Submitted Template')) }

    it 'filters by status' do
      visit business_manager_job_form_submissions_path

      select 'Submitted', from: 'Status'
      click_button 'Filter'

      expect(page).to have_content('Submitted Template')
      expect(page).not_to have_content('Service Checklist')
    end
  end

  describe 'viewing a submission' do
    let(:submission) { create(:job_form_submission, business: business, booking: booking, job_form_template: template) }

    before do
      template.form_fields.each do |field|
        submission.set_response(field['id'], 'Test response')
      end
      submission.save!
    end

    it 'displays the submission details' do
      visit business_manager_job_form_submission_path(submission)

      expect(page).to have_content(template.name)
      expect(page).to have_content('Test response')
    end
  end

  describe 'approving a submission' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'approves a submitted form' do
      visit business_manager_job_form_submission_path(submission)

      click_button 'Approve'

      expect(page).to have_content('approved')
      submission.reload
      expect(submission.approved?).to be true
    end
  end

  describe 'requesting revision' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'requests revision with notes' do
      visit business_manager_job_form_submission_path(submission)

      fill_in 'Notes', with: 'Please add more details about the equipment condition'
      click_button 'Request Revision'

      expect(page).to have_content('requires revision')
      submission.reload
      expect(submission.requires_revision?).to be true
    end
  end

  describe 'viewing submissions by booking' do
    it 'shows all submissions for a booking' do
      submission1 = create(:job_form_submission, business: business, booking: booking, job_form_template: template)
      template2 = create(:job_form_template, business: business, name: 'Another Template')
      submission2 = create(:job_form_submission, business: business, booking: booking, job_form_template: template2)

      visit by_booking_business_manager_job_form_submissions_path(booking_id: booking.id)

      expect(page).to have_content('Service Checklist')
      expect(page).to have_content('Another Template')
    end
  end
end
