require 'rails_helper'

RSpec.describe TemplatePageSection, type: :model do
  # Note: This model's table doesn't exist in the database anymore
  # We only test for the existence of methods and scopes
  
  describe 'model structure' do
    it 'responds to expected methods' do
      expect(TemplatePageSection).to respond_to(:active)
      expect(TemplatePageSection).to respond_to(:ordered)
    end
    
    it 'defines section_type as an enum' do
      expect(TemplatePageSection.section_types).to include('header', 'text', 'image', 'gallery', 
                                                          'contact_form', 'service_list', 'product_list', 
                                                          'testimonial', 'cta', 'custom')
    end
  end
end 