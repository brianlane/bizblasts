# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::JobFormSubmissions', type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business) }
  let(:booking) { create(:booking, business: business, service: service) }
  let(:template) { create(:job_form_template, :with_fields, business: business) }

  before do
    host! "#{business.subdomain}.lvh.me"
    sign_in user
    ActsAsTenant.current_tenant = business
  end

  describe 'GET /manage/job_form_submissions' do
    it 'returns a successful response' do
      get business_manager_job_form_submissions_path

      expect(response).to be_successful
    end

    it 'displays submissions for the business' do
      submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

      get business_manager_job_form_submissions_path

      expect(response.body).to include(template.name)
    end

    context 'with status filter' do
      let!(:draft_submission) { create(:job_form_submission, business: business, booking: booking, job_form_template: template, status: :draft) }
      let!(:submitted_submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: create(:job_form_template, business: business)) }

      it 'filters by status' do
        get business_manager_job_form_submissions_path, params: { status: 'submitted' }

        expect(response).to be_successful
      end
    end

    context 'with booking filter' do
      it 'filters by booking_id' do
        submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

        get business_manager_job_form_submissions_path, params: { booking_id: booking.id }

        expect(response).to be_successful
      end
    end

    context 'with date range filter' do
      it 'filters by date range' do
        submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

        get business_manager_job_form_submissions_path, params: {
          from_date: Date.current.to_s,
          to_date: Date.current.to_s
        }

        expect(response).to be_successful
      end
    end
  end

  describe 'GET /manage/job_form_submissions/:id' do
    let(:submission) { create(:job_form_submission, business: business, booking: booking, job_form_template: template) }

    it 'returns a successful response' do
      get business_manager_job_form_submission_path(submission)

      expect(response).to be_successful
    end

    it 'displays the submission details' do
      get business_manager_job_form_submission_path(submission)

      expect(response.body).to include(template.name)
    end
  end

  describe 'GET /manage/job_form_submissions/by_booking' do
    it 'returns a successful response' do
      submission = create(:job_form_submission, business: business, booking: booking, job_form_template: template)

      get by_booking_business_manager_job_form_submissions_path, params: { booking_id: booking.id }

      expect(response).to be_successful
    end
  end

  describe 'PATCH /manage/job_form_submissions/:id/approve' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'approves a submitted form' do
      patch approve_business_manager_job_form_submission_path(submission)

      submission.reload
      expect(submission.approved?).to be true
      expect(submission.approved_by_user).to eq(user)
    end

    it 'redirects to the submission page' do
      patch approve_business_manager_job_form_submission_path(submission)

      expect(response).to redirect_to(business_manager_job_form_submission_path(submission))
    end

    context 'for a draft form' do
      let(:draft_submission) { create(:job_form_submission, business: business, booking: booking, job_form_template: template, status: :draft) }

      it 'does not approve' do
        patch approve_business_manager_job_form_submission_path(draft_submission)

        draft_submission.reload
        expect(draft_submission.draft?).to be true
      end
    end

    context 'with JSON format' do
      it 'returns JSON response' do
        patch approve_business_manager_job_form_submission_path(submission), as: :json

        expect(response).to be_successful
        expect(JSON.parse(response.body)['status']).to eq('approved')
      end
    end
  end

  describe 'PATCH /manage/job_form_submissions/:id/request_revision' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }

    it 'requests revision for a submitted form' do
      patch request_revision_business_manager_job_form_submission_path(submission), params: { notes: 'Please add more detail' }

      submission.reload
      expect(submission.requires_revision?).to be true
      expect(submission.notes).to eq('Please add more detail')
    end

    it 'redirects to the submission page' do
      patch request_revision_business_manager_job_form_submission_path(submission), params: { notes: 'Fix this' }

      expect(response).to redirect_to(business_manager_job_form_submission_path(submission))
    end

    context 'with JSON format' do
      it 'returns JSON response' do
        patch request_revision_business_manager_job_form_submission_path(submission), params: { notes: 'Fix this' }, as: :json

        expect(response).to be_successful
        expect(JSON.parse(response.body)['status']).to eq('requires_revision')
      end
    end
  end

  describe 'authorization' do
    let(:other_business) { create(:business) }
    let(:other_booking) do
      ActsAsTenant.without_tenant do
        create(:booking, business: other_business)
      end
    end
    let(:other_template) do
      ActsAsTenant.without_tenant do
        create(:job_form_template, business: other_business)
      end
    end
    let(:other_submission) do
      ActsAsTenant.without_tenant do
        create(:job_form_submission, business: other_business, booking: other_booking, job_form_template: other_template)
      end
    end

    it 'redirects when accessing submissions from other businesses' do
      get business_manager_job_form_submission_path(other_submission)

      expect(response).to redirect_to(business_manager_job_form_submissions_path)
    end
  end
end
