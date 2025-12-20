# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobFormTemplate, type: :model do
  subject(:template) { build(:job_form_template) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:service_job_forms).dependent(:destroy) }
    it { is_expected.to have_many(:services).through(:service_job_forms) }
    it { is_expected.to have_many(:job_form_submissions).dependent(:restrict_with_error) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:business) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:form_type) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_length_of(:description).is_at_most(2000) }

    context 'uniqueness' do
      subject(:template) { create(:job_form_template) }

      it 'validates name uniqueness within business' do
        duplicate = build(:job_form_template, business: template.business, name: template.name)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different businesses' do
        other_business = create(:business)
        duplicate = build(:job_form_template, business: other_business, name: template.name)
        expect(duplicate).to be_valid
      end
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:form_type).with_values(checklist: 0, inspection: 1, completion_report: 2, custom: 3) }
  end

  describe 'scopes' do
    let!(:business) { create(:business) }
    let!(:active_template) { create(:job_form_template, business: business, active: true, position: 1) }
    let!(:inactive_template) { create(:job_form_template, business: business, active: false, position: 0) }

    describe '.ordered' do
      it 'orders by position and name' do
        expect(business.job_form_templates.ordered).to eq([inactive_template, active_template])
      end
    end

    describe '.active' do
      it 'returns only active templates' do
        expect(business.job_form_templates.active).to contain_exactly(active_template)
      end
    end

    describe '.inactive' do
      it 'returns only inactive templates' do
        expect(business.job_form_templates.inactive).to contain_exactly(inactive_template)
      end
    end
  end

  describe '#form_fields' do
    it 'returns empty array for new template' do
      expect(template.form_fields).to eq([])
    end

    it 'returns fields from the fields JSONB column' do
      template = create(:job_form_template, :with_fields)
      expect(template.form_fields.length).to eq(3)
      expect(template.form_fields.first['type']).to eq('checkbox')
    end
  end

  describe '#add_field' do
    it 'adds a new field to the template' do
      template.save!
      template.add_field(label: 'Test Field', type: 'text', required: true)

      expect(template.form_fields.length).to eq(1)
      expect(template.form_fields.first['label']).to eq('Test Field')
      expect(template.form_fields.first['type']).to eq('text')
      expect(template.form_fields.first['required']).to be true
      expect(template.form_fields.first['id']).to be_present
    end
  end

  describe '#remove_field' do
    it 'removes a field by ID' do
      template = create(:job_form_template, :with_fields)
      field_id = template.form_fields.first['id']

      template.remove_field(field_id)

      expect(template.form_fields.none? { |f| f['id'] == field_id }).to be true
    end
  end

  describe '#required_field_count' do
    it 'returns count of required fields' do
      template = create(:job_form_template, :with_fields)
      expect(template.required_field_count).to eq(2) # checkbox and select are required
    end
  end

  describe '#has_photo_fields?' do
    it 'returns false when no photo fields' do
      template = create(:job_form_template, :with_fields)
      expect(template.has_photo_fields?).to be false
    end

    it 'returns true when photo fields exist' do
      template = create(:job_form_template, :with_photo_field)
      expect(template.has_photo_fields?).to be true
    end
  end

  describe '#duplicate' do
    it 'creates a copy of the template' do
      original = create(:job_form_template, :with_fields, name: 'Original Template')
      copy = original.duplicate

      expect(copy).not_to be_persisted
      expect(copy.name).to eq('Original Template (Copy)')
      expect(copy.form_fields.length).to eq(original.form_fields.length)
      expect(copy.business).to eq(original.business)
    end

    it 'accepts custom name' do
      original = create(:job_form_template)
      copy = original.duplicate(new_name: 'Custom Copy')

      expect(copy.name).to eq('Custom Copy')
    end
  end

  describe 'field type validation' do
    it 'validates field type is from allowed list' do
      template = build(:job_form_template)
      template.fields = {
        'fields' => [
          { 'id' => SecureRandom.uuid, 'type' => 'invalid_type', 'label' => 'Test' }
        ]
      }

      expect(template).not_to be_valid
      expect(template.errors[:fields].first).to include('invalid type')
    end

    it 'validates select fields have options' do
      template = build(:job_form_template)
      template.fields = {
        'fields' => [
          { 'id' => SecureRandom.uuid, 'type' => 'select', 'label' => 'Test', 'options' => 'not an array' }
        ]
      }

      expect(template).not_to be_valid
      expect(template.errors[:fields].first).to include('must have options array')
    end
  end
end
