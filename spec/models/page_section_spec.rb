require 'rails_helper'

RSpec.describe PageSection, type: :model do
  let(:business) { create(:business) }
  let(:page) { create(:page, business: business) }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  describe 'associations' do
    it { should belong_to(:page) }
  end

  describe 'validations' do
    it { should validate_presence_of(:section_type) }
    it { should validate_presence_of(:position) }
    it { should validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
    
    context 'when content is required' do
      subject { build(:page_section, section_type: 'text', page: page) }
      it { should validate_presence_of(:content) }
    end
    
    context 'when content is optional' do
      subject { build(:page_section, section_type: 'contact_form', page: page, content: nil) }
      it { should be_valid }
    end
  end

  describe 'enums' do
    it { should define_enum_for(:section_type).with_values([
      :header, :text, :image, :gallery, :contact_form, :service_list, :product_list, 
      :testimonial, :cta, :custom, :hero_banner, :product_grid, 
      :team_showcase, :pricing_table, :faq_section, :social_media, 
      :video_embed, :map_location, :newsletter_signup
    ]) }
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active page sections' do
        active_section = create(:page_section, page: page, active: true)
        inactive_section = create(:page_section, page: page, active: false)
        
        expect(PageSection.active).to include(active_section)
        expect(PageSection.active).not_to include(inactive_section)
      end
    end

    describe '.ordered' do
      it 'returns page sections ordered by position' do
        third_section = create(:page_section, page: page, position: 3)
        first_section = create(:page_section, page: page, position: 1)
        second_section = create(:page_section, page: page, position: 2)
        
        expect(PageSection.ordered.to_a).to eq([first_section, second_section, third_section])
      end
    end
  end
end 