require 'rails_helper'

RSpec.describe "business_manager/products/new.html.erb", type: :view do
  let(:business) { create(:business) }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:product) { Product.new(business: business) }

  before(:each) do
    # Required for view rendering
    allow(view).to receive(:current_user).and_return(manager_user)
    allow(view).to receive(:current_business).and_return(business)
    
    # Assign instance variables expected by the view and form partial
    assign(:product, product)
    assign(:current_business, business)
    
    render
  end

  it "renders the new product form" do
    # Check for the form targeting the correct path
    expect(rendered).to have_selector("form[action='/manage/products'][method='post']") do |form|
      expect(form).to have_field('product[name]')
      expect(form).to have_field('product[description]')
      expect(form).to have_field('product[price]')
      expect(form).to have_field('product[active]', type: 'checkbox')
      expect(form).to have_field('product[featured]', type: 'checkbox')
      expect(form).to have_field('product[tips_enabled]', type: 'checkbox')
      expect(form).to have_button('Create Product')
    end
  end

  it "includes the tips_enabled checkbox with proper labeling" do
    expect(rendered).to have_field('product[tips_enabled]', type: 'checkbox')
    expect(rendered).to have_content('Enable tips')
  end

  it "renders the tips_enabled checkbox in the Status Options section" do
    # Look for the checkbox within the Status Options area
    expect(rendered).to have_css('.space-y-3') do |status_section|
      expect(status_section).to have_field('product[tips_enabled]', type: 'checkbox')
    end
  end
end 