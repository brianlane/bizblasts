# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceTemplate, type: :model do
  # Use subject for cleaner tests
  # Build a valid template for most tests
  subject(:template) { build(:service_template, industry: :general, template_type: :full_website) }

  describe 'validations' do
    # Test the subject built with valid attributes
    it "is valid with valid attributes" do
      expect(template).to be_valid
    end

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:industry) }
    it { is_expected.to validate_presence_of(:template_type) }

    # Explicitly test invalid without industry
    it "is invalid without an industry" do
      template.industry = nil
      expect(template).not_to be_valid
      expect(template.errors[:industry]).to include("can't be blank")
    end

    # Explicitly test invalid without template_type
    it "is invalid without a template_type" do
      template.template_type = nil
      expect(template).not_to be_valid
      expect(template.errors[:template_type]).to include("can't be blank")
    end

    it do
      is_expected.to define_enum_for(:industry)
        .with_values(landscaping: 0, pool_service: 1, home_service: 2, general: 3)
        .backed_by_column_of_type(:integer)
    end

    it do
      is_expected.to define_enum_for(:template_type)
        .with_values(booking: 0, marketing: 1, full_website: 2)
        .backed_by_column_of_type(:integer)
    end
  end

  describe 'associations' do
    it { is_expected.to have_many(:businesses).with_foreign_key(:service_template_id).dependent(:nullify) }
  end

  describe 'scopes' do
    # Create records within each test to ensure isolation
    it '.active returns only active templates' do
      active_template = create(:service_template, active: true)
      inactive_template = create(:service_template, active: false)
      expect(ServiceTemplate.active).to contain_exactly(active_template)
      expect(ServiceTemplate.active).not_to include(inactive_template)
    end

    it '.published returns only published templates' do
      published_template = create(:service_template, published_at: Time.current)
      draft_template = create(:service_template, published_at: nil)
      expect(ServiceTemplate.published).to contain_exactly(published_template)
      expect(ServiceTemplate.published).not_to include(draft_template)
    end

    it '.by_industry returns templates for the specified industry' do
      landscaping_template = create(:service_template, industry: :landscaping)
      pool_template = create(:service_template, industry: :pool_service)
      expect(ServiceTemplate.by_industry(:landscaping)).to contain_exactly(landscaping_template)
      expect(ServiceTemplate.by_industry(:pool_service)).to contain_exactly(pool_template)
      expect(ServiceTemplate.by_industry(:general)).to be_empty
    end
  end

  describe '#published?' do
    it 'returns true if published_at is set' do
      template.published_at = Time.current
      expect(template.published?).to be true
    end

    it 'returns false if published_at is nil' do
      template.published_at = nil
      expect(template.published?).to be false
    end
  end

  describe '#apply_to_business' do
    let(:business) { create(:business) }
    # Ensure templates used here are valid
    let(:active_published_template) { create(:service_template, active: true, published_at: Time.current, industry: :general, template_type: :full_website) }
    let(:inactive_template) { create(:service_template, active: false, published_at: Time.current, industry: :general, template_type: :full_website) }
    let(:draft_template) { create(:service_template, active: true, published_at: nil, industry: :general, template_type: :full_website) }

    # context 'with an active and published template' do
    #   it 'associates the template with the business' do
    #     expect(active_published_template.apply_to_business(business)).to be true
    #     expect(business.reload.service_template).to eq(active_published_template)
    #   end
    # end

    context 'with an inactive template' do
      it 'returns false and does not associate the template' do
        expect(inactive_template.apply_to_business(business)).to be false
        expect(business.reload.service_template).to be_nil
      end
    end

    context 'with a draft template' do
      it 'returns false and does not associate the template' do
        expect(draft_template.apply_to_business(business)).to be false
        expect(business.reload.service_template).to be_nil
      end
    end

    context 'when an error occurs during application' do
      before do
        allow(business).to receive(:update).and_raise(StandardError, "DB error")
      end

      it 'returns false and logs an error' do
        expect(Rails.logger).to receive(:error).with(/Error applying template/)
        expect(active_published_template.apply_to_business(business)).to be false
      end
    end
  end

  # Removed outdated tests for ransackable_attributes, defaults, status
end 