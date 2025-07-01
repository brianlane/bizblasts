require 'rails_helper'

RSpec.describe "business_manager/products/edit.html.erb", type: :view do
  let(:business) { create(:business) }
  let(:manager_user) { create(:user, :manager, business: business) }
  let!(:product) { create(:product, business: business, name: "Test Product", price: 99.99, tips_enabled: true) }

  before(:each) do
    # Required for view rendering
    allow(view).to receive(:current_user).and_return(manager_user)
    allow(view).to receive(:current_business).and_return(business)
    
    # Assign instance variables expected by the view and form partial
    assign(:product, product)
    assign(:current_business, business)
    
    render
  end

  it "renders the edit product form with existing values" do
    # Check for the form targeting the correct update path
    expect(rendered).to have_selector("form[action='/manage/products/#{product.id}'][method='post']") do |form|
      expect(form).to have_field('_method', type: 'hidden', with: 'patch')
      
      # Check that fields are pre-filled with existing values
      expect(form).to have_field('product[name]', with: product.name)
      expect(form).to have_field('product[price]', with: product.price)
      expect(form).to have_field('product[active]', type: 'checkbox')
      expect(form).to have_field('product[featured]', type: 'checkbox')
      expect(form).to have_field('product[tips_enabled]', type: 'checkbox', checked: true)
      expect(form).to have_button('Update Product')
    end
  end

  it "includes the tips_enabled checkbox with proper labeling" do
    expect(rendered).to have_field('product[tips_enabled]', type: 'checkbox')
    expect(rendered).to have_content('Enable tips')
  end

  it "renders the tips_enabled checkbox as checked when product has tips enabled" do
    expect(rendered).to have_field('product[tips_enabled]', type: 'checkbox', checked: true)
  end

  context "when product has tips disabled" do
    let!(:product) { create(:product, business: business, tips_enabled: false) }

    it "renders the tips_enabled checkbox as unchecked" do
      allow(view).to receive(:current_business).and_return(business)
      assign(:product, product)
      render
      expect(rendered).to have_field('product[tips_enabled]', type: 'checkbox', checked: false)
    end
  end
end 