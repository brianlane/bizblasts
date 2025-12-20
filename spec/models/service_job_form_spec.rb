# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceJobForm, type: :model do
  let(:business) { create(:business) }
  let(:service) { create(:service, business: business) }
  let(:template) { create(:job_form_template, business: business) }

  subject(:service_job_form) { build(:service_job_form, service: service, job_form_template: template) }

  describe 'associations' do
    it { is_expected.to belong_to(:service) }
    it { is_expected.to belong_to(:job_form_template) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:service) }
    it { is_expected.to validate_presence_of(:job_form_template) }
    it { is_expected.to validate_presence_of(:timing) }

    context 'uniqueness' do
      before { create(:service_job_form, service: service, job_form_template: template) }

      it 'prevents duplicate assignments' do
        duplicate = build(:service_job_form, service: service, job_form_template: template)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:job_form_template_id]).to include('is already assigned to this service')
      end
    end

    context 'same business validation' do
      it 'rejects template from different business' do
        other_business = create(:business)
        other_template = create(:job_form_template, business: other_business)

        service_job_form = build(:service_job_form, service: service, job_form_template: other_template)
        expect(service_job_form).not_to be_valid
        expect(service_job_form.errors[:job_form_template]).to include('must belong to the same business as the service')
      end
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:timing).with_values(before_service: 0, during_service: 1, after_service: 2) }
  end

  describe 'scopes' do
    let!(:required_form) { create(:service_job_form, :required, service: service, job_form_template: template) }
    let!(:optional_form) { create(:service_job_form, service: service, job_form_template: create(:job_form_template, business: business)) }
    let!(:before_form) { create(:service_job_form, timing: :before_service, service: service, job_form_template: create(:job_form_template, business: business)) }
    let!(:during_form) { create(:service_job_form, timing: :during_service, service: service, job_form_template: create(:job_form_template, business: business)) }
    let!(:after_form) { create(:service_job_form, timing: :after_service, service: service, job_form_template: create(:job_form_template, business: business)) }

    describe '.required_forms' do
      it 'returns only required forms' do
        expect(ServiceJobForm.required_forms).to include(required_form)
        expect(ServiceJobForm.required_forms).not_to include(optional_form)
      end
    end

    describe '.before_forms' do
      it 'returns forms with before_service timing' do
        expect(ServiceJobForm.before_forms).to include(before_form)
      end
    end

    describe '.during_forms' do
      it 'returns forms with during_service timing' do
        expect(ServiceJobForm.during_forms).to include(during_form)
      end
    end

    describe '.after_forms' do
      it 'returns forms with after_service timing' do
        expect(ServiceJobForm.after_forms).to include(after_form)
      end
    end
  end

  describe '#display_name' do
    it 'returns template name with timing' do
      service_job_form = create(:service_job_form, service: service, job_form_template: template, timing: :before_service)
      expect(service_job_form.display_name).to eq("#{template.name} (Before)")
    end
  end

  describe '#timing_display' do
    it 'returns human-readable timing' do
      expect(build(:service_job_form, timing: :before_service).timing_display).to eq('Before')
      expect(build(:service_job_form, timing: :during_service).timing_display).to eq('During')
      expect(build(:service_job_form, timing: :after_service).timing_display).to eq('After')
    end
  end

  describe 'delegation' do
    it 'delegates business to service' do
      expect(service_job_form.business).to eq(service.business)
      expect(service_job_form.business_id).to eq(service.business_id)
    end
  end
end
