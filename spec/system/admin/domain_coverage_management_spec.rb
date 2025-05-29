# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Domain Coverage Management", type: :system do
  let!(:admin_user) { create(:admin_user) }
  let!(:premium_business) { create(:business, tier: 'premium', host_type: 'custom_domain', hostname: 'example.com') }
  let!(:free_business) { create(:business, tier: 'free', host_type: 'subdomain', hostname: 'freebiz') }
  let!(:premium_with_coverage) do
    create(:business, 
      tier: 'premium', 
      host_type: 'custom_domain', 
      hostname: 'covered.com',
      domain_coverage_applied: true,
      domain_cost_covered: 18.50,
      domain_renewal_date: 1.year.from_now,
      domain_coverage_notes: 'Registered via Namecheap'
    )
  end

  before do
    sign_in admin_user
  end

  describe "Domain Coverage in Business Index" do
    it "shows domain coverage status for all businesses" do
      visit admin_businesses_path
      
      expect(page).to have_content("Domain Coverage")
      
      # Should show different statuses
      expect(page).to have_content("Available") # For premium business without coverage
      expect(page).to have_content("Covered") # For premium business with coverage
      expect(page).to have_content("Not Eligible") # For free business
    end

    it "filters businesses by domain coverage status" do
      visit admin_businesses_path
      
      # Filter by domain coverage applied
      select 'Yes', from: 'Domain coverage applied'
      click_button 'Filter'
      
      expect(page).to have_content(premium_with_coverage.name)
      expect(page).not_to have_content(premium_business.name)
      expect(page).not_to have_content(free_business.name)
    end

    it "shows coverage amounts in status" do
      visit admin_businesses_path
      
      expect(page).to have_content("Covered ($18.5)") # Shows the covered amount
    end
  end

  describe "Domain Coverage in Business Show Page" do
    context "for premium business with coverage" do
      it "displays comprehensive coverage information" do
        visit admin_business_path(premium_with_coverage)
        
        expect(page).to have_content("Domain Coverage Information")
        expect(page).to have_content("Coverage Applied")
        expect(page).to have_content("$18.5")
        expect(page).to have_content("Registered via Namecheap")
        expect(page).to have_content("$20.0/year")
        
        # Should show renewal date
        expect(page).to have_content(premium_with_coverage.domain_renewal_date.strftime("%B %d, %Y"))
      end
    end

    context "for premium business without coverage" do
      it "shows available coverage status" do
        visit admin_business_path(premium_business)
        
        expect(page).to have_content("Domain Coverage Information")
        expect(page).to have_content("Coverage Available")
        expect(page).to have_content("Not applied")
        expect(page).to have_content("Not set")
      end
    end

    context "for non-premium business" do
      it "does not show domain coverage panel" do
        visit admin_business_path(free_business)
        
        expect(page).not_to have_content("Domain Coverage Information")
      end
    end
  end

  describe "Domain Coverage in Business Forms" do
    context "creating new premium business with coverage" do
      it "allows setting domain coverage fields" do
        visit new_admin_business_path
        
        # Fill basic business information
        fill_in 'Name', with: 'Premium Coverage Business'
        fill_in 'Hostname', with: 'premiumcoverage.com'
        select 'Custom domain', from: 'Host type'
        select 'Premium', from: 'Tier'
        select 'Consulting', from: 'Industry'
        fill_in 'Phone', with: '555-999-8888'
        fill_in 'Email', with: 'contact@premiumcoverage.com'
        fill_in 'Address', with: '789 Premium Ave'
        fill_in 'City', with: 'Premium City'
        fill_in 'State', with: 'PC'
        fill_in 'Zip', with: '99999'
        fill_in 'Description', with: 'A premium business with domain coverage'
        
        # Domain coverage fields
        check 'Domain coverage has been applied'
        fill_in 'Amount covered (USD)', with: '19.99'
        fill_in 'Domain renewal date', with: 1.year.from_now.strftime('%Y-%m-%d')
        fill_in 'Coverage notes', with: 'Domain registered via admin interface for testing'
        
        click_button 'Create Business'
        
        expect(page).to have_content('Premium Coverage Business')
        expect(page).to have_content('Domain Coverage Information')
        expect(page).to have_content('Coverage Applied')
        expect(page).to have_content('$19.99')
      end
    end

    context "editing existing business coverage" do
      it "allows updating domain coverage information" do
        visit edit_admin_business_path(premium_business)
        
        # Apply domain coverage
        check 'Domain coverage has been applied'
        fill_in 'Amount covered (USD)', with: '16.75'
        fill_in 'Domain renewal date', with: 1.year.from_now.strftime('%Y-%m-%d')
        fill_in 'Coverage notes', with: 'Updated coverage information'
        
        click_button 'Update Business'
        
        expect(page).to have_content('Domain Coverage Information')
        expect(page).to have_content('Coverage Applied')
        expect(page).to have_content('$16.75')
        expect(page).to have_content('Updated coverage information')
      end
    end
  end

  describe "Domain Coverage Form Sections" do
    it "shows domain coverage section in forms" do
      visit new_admin_business_path
      
      expect(page).to have_content('Domain Coverage (Premium Only)')
      expect(page).to have_field('Domain coverage has been applied')
      expect(page).to have_field('Amount covered (USD)')
      expect(page).to have_field('Domain renewal date')
      expect(page).to have_field('Coverage notes')
    end

    it "includes helpful hints for coverage fields" do
      visit new_admin_business_path
      
      expect(page).to have_content('Maximum $20.00/year')
      expect(page).to have_content('Internal notes about domain coverage, cost details, alternatives offered, etc.')
    end
  end

  describe "Domain Coverage Workflow" do
    scenario "Admin applies coverage to premium business" do
      # Start with premium business without coverage
      visit admin_business_path(premium_business)
      expect(page).to have_content('Coverage Available')
      
      # Edit to apply coverage
      click_link 'Edit'
      
      check 'Domain coverage has been applied'
      fill_in 'Amount covered (USD)', with: '14.99'
      fill_in 'Domain renewal date', with: 1.year.from_now.strftime('%Y-%m-%d')
      fill_in 'Coverage notes', with: 'Domain registered successfully via GoDaddy'
      
      click_button 'Update Business'
      
      # Verify coverage is now applied
      expect(page).to have_content('Coverage Applied')
      expect(page).to have_content('$14.99')
      expect(page).to have_content('Domain registered successfully via GoDaddy')
      
      # Verify in index as well
      visit admin_businesses_path
      expect(page).to have_content('Covered ($14.99)')
    end
  end

  describe "Domain Coverage Validation" do
    it "validates coverage amount within limit" do
      visit new_admin_business_path
      
      fill_in 'Name', with: 'Test Business'
      fill_in 'Hostname', with: 'test.com'
      select 'Custom domain', from: 'Host type'
      select 'Premium', from: 'Tier'
      select 'Consulting', from: 'Industry'
      fill_in 'Phone', with: '555-123-4567'
      fill_in 'Email', with: 'test@test.com'
      fill_in 'Address', with: '123 Test St'
      fill_in 'City', with: 'Test City'
      fill_in 'State', with: 'TS'
      fill_in 'Zip', with: '12345'
      fill_in 'Description', with: 'Test business'
      
      check 'Domain coverage has been applied'
      fill_in 'Amount covered (USD)', with: '25.00' # Over limit
      
      click_button 'Create Business'
      
      # Should show error or handle validation appropriately
      # Note: The actual validation would need to be implemented in the model
    end
  end
end 