require 'rails_helper'

RSpec.describe PageSection, type: :model do
  describe 'associations' do
    it { should belong_to(:page) }
  end

  describe 'validations' do
    it { should validate_presence_of(:section_type) }
    it { should validate_presence_of(:content) }
    it { should validate_presence_of(:position) }
    it { should validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe 'enums' do
    it { should define_enum_for(:section_type).with_values([:header, :text, :image, :gallery, :contact_form, :service_list, :testimonial, :cta, :custom]) }
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active page sections' do
        active_section = create(:page_section, active: true)
        inactive_section = create(:page_section, active: false)
        
        expect(PageSection.active).to include(active_section)
        expect(PageSection.active).not_to include(inactive_section)
      end
    end

    describe '.ordered' do
      it 'returns page sections ordered by position' do
        page = create(:page)
        third_section = create(:page_section, page: page, position: 3)
        first_section = create(:page_section, page: page, position: 1)
        second_section = create(:page_section, page: page, position: 2)
        
        expect(PageSection.ordered.to_a).to eq([first_section, second_section, third_section])
      end
    end
  end
end 