# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobFormSubmission, type: :model do
  let(:business) { create(:business) }
  let(:service) { create(:service, business: business) }
  let(:booking) { create(:booking, business: business, service: service) }
  let(:template) { create(:job_form_template, :with_fields, business: business) }

  subject(:submission) do
    build(:job_form_submission, business: business, booking: booking, job_form_template: template)
  end

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:booking) }
    it { is_expected.to belong_to(:job_form_template) }
    it { is_expected.to belong_to(:staff_member).optional }
    it { is_expected.to belong_to(:submitted_by_user).class_name('User').optional }
    it { is_expected.to belong_to(:approved_by_user).class_name('User').optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:business) }
    it { is_expected.to validate_presence_of(:booking) }
    it { is_expected.to validate_presence_of(:job_form_template) }
    it { is_expected.to validate_presence_of(:status) }

    context 'same business validation' do
      it 'rejects booking from different business' do
        other_business = create(:business)
        other_booking = create(:booking, business: other_business)

        submission = build(:job_form_submission, business: business, booking: other_booking, job_form_template: template)
        expect(submission).not_to be_valid
        expect(submission.errors[:business]).to include('must match the booking business')
      end

      it 'rejects template from different business' do
        other_business = create(:business)
        other_template = create(:job_form_template, business: other_business)

        submission = build(:job_form_submission, business: business, booking: booking, job_form_template: other_template)
        expect(submission).not_to be_valid
        expect(submission.errors[:job_form_template]).to include('must belong to the same business as the booking')
      end
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:status).with_values(draft: 0, submitted: 1, approved: 2, requires_revision: 3) }
  end

  describe 'scopes' do
    let!(:draft_submission) { create(:job_form_submission, business: business, booking: booking, job_form_template: template, status: :draft) }
    let!(:submitted_submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: create(:job_form_template, business: business)) }
    let!(:approved_submission) { create(:job_form_submission, :approved, business: business, booking: booking, job_form_template: create(:job_form_template, business: business)) }

    describe '.pending_review' do
      it 'returns submitted forms' do
        expect(JobFormSubmission.pending_review).to contain_exactly(submitted_submission)
      end
    end

    describe '.completed' do
      it 'returns approved and requires_revision forms' do
        expect(JobFormSubmission.completed).to contain_exactly(approved_submission)
      end
    end

    describe '.for_booking' do
      it 'returns forms for specific booking' do
        expect(JobFormSubmission.for_booking(booking.id)).to include(draft_submission)
      end
    end
  end

  describe '#response_for' do
    it 'returns response for a given field ID' do
      field_id = template.form_fields.first['id']
      submission.responses = { field_id => 'test value' }

      expect(submission.response_for(field_id)).to eq('test value')
    end

    it 'returns nil for non-existent field' do
      expect(submission.response_for('non-existent-id')).to be_nil
    end

    it 'handles nil responses without crashing (database NULL case)' do
      # Simulate a submission loaded from DB with NULL responses column
      submission.responses = nil

      # Should not raise NoMethodError
      expect { submission.response_for('any-field') }.not_to raise_error
      expect(submission.response_for('any-field')).to be_nil
    end
  end

  describe '#set_response' do
    it 'sets response for a given field ID' do
      field_id = 'test-field-id'
      submission.set_response(field_id, 'new value')

      expect(submission.responses[field_id]).to eq('new value')
    end
  end

  describe '#all_required_fields_filled?' do
    it 'returns true when all required fields are filled' do
      template.form_fields.each do |field|
        if field['required']
          submission.responses[field['id']] = 'value'
        end
      end

      expect(submission.all_required_fields_filled?).to be true
    end

    it 'returns false when required fields are missing' do
      expect(submission.all_required_fields_filled?).to be false
    end
  end

  describe '#completion_percentage' do
    it 'returns 0 when no fields are filled' do
      expect(submission.completion_percentage).to eq(0)
    end

    it 'returns percentage based on filled fields' do
      field_id = template.form_fields.first['id']
      submission.responses = { field_id => 'value' }

      expect(submission.completion_percentage).to eq(33) # 1 of 3 fields = 33%
    end

    it 'returns 100 when all fields are filled' do
      template.form_fields.each { |f| submission.responses[f['id']] = 'value' }

      expect(submission.completion_percentage).to eq(100)
    end
  end

  describe '#submit!' do
    before do
      template.form_fields.each { |f| submission.responses[f['id']] = f['required'] ? 'value' : nil }
      submission.save!
    end

    it 'submits when all required fields are filled' do
      user = create(:user)
      expect(submission.submit!(user: user)).to be true
      expect(submission.submitted?).to be true
      expect(submission.submitted_by_user).to eq(user)
      expect(submission.submitted_at).to be_present
    end

    it 'fails when required fields are missing' do
      submission.update!(responses: {})
      expect(submission.submit!).to be false
      expect(submission.draft?).to be true
    end
  end

  describe '#approve!' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }
    let(:approver) { create(:user) }

    it 'approves a submitted form' do
      expect(submission.approve!(user: approver)).to be true
      expect(submission.approved?).to be true
      expect(submission.approved_by_user).to eq(approver)
      expect(submission.approved_at).to be_present
    end

    it 'fails for draft forms' do
      draft = create(:job_form_submission, business: business, booking: booking, job_form_template: template, status: :draft)
      expect(draft.approve!(user: approver)).to be false
    end
  end

  describe '#request_revision!' do
    let(:submission) { create(:job_form_submission, :submitted, business: business, booking: booking, job_form_template: template) }
    let(:reviewer) { create(:user) }

    it 'requests revision with notes' do
      expect(submission.request_revision!(user: reviewer, notes: 'Please add more detail')).to be true
      expect(submission.requires_revision?).to be true
      expect(submission.notes).to eq('Please add more detail')
    end
  end

  describe '#editable?' do
    it 'returns true for draft' do
      expect(build(:job_form_submission, status: :draft).editable?).to be true
    end

    it 'returns true for requires_revision' do
      expect(build(:job_form_submission, status: :requires_revision).editable?).to be true
    end

    it 'returns false for submitted' do
      expect(build(:job_form_submission, status: :submitted).editable?).to be false
    end

    it 'returns false for approved' do
      expect(build(:job_form_submission, status: :approved).editable?).to be false
    end
  end

  describe '#responses_with_labels' do
    it 'returns responses with field labels' do
      field = template.form_fields.first
      submission.responses = { field['id'] => 'test value' }

      result = submission.responses_with_labels
      expect(result.first[:label]).to eq(field['label'])
      expect(result.first[:value]).to eq('test value')
    end

    it 'handles nil responses without crashing' do
      submission.responses = nil

      # Should not raise NoMethodError
      expect { submission.responses_with_labels }.not_to raise_error

      result = submission.responses_with_labels
      expect(result).to be_an(Array)
      expect(result.first[:value]).to be_nil
    end
  end
end
