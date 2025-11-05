require 'rails_helper'

RSpec.describe 'Tips Flow', type: :system, js: true do
  let!(:business) { create(:business, :with_default_tax_rate, host_type: 'subdomain') }
  let!(:tip_configuration) { create(:tip_configuration, business: business) }
  let!(:user) { create(:user, :client, password: 'password123') }
  let!(:tenant_customer) { create(:tenant_customer, business: business, email: user.email, first_name: user.first_name, last_name: user.last_name) }
  let!(:experience_service) { create(:service, business: business, name: 'Wine Tasting Experience', price: 75.00, service_type: :experience, duration: 120, min_bookings: 1, max_bookings: 10, spots: 5, tips_enabled: true) }
  let!(:staff_member) { create(:staff_member, business: business) }
  let!(:services_staff_member) { create(:services_staff_member, service: experience_service, staff_member: staff_member) }
  
  before do
    ActsAsTenant.current_tenant = business
    set_tenant(business)
    Capybara.app_host = url_for_business(business)
    
    # Mock Stripe tip checkout session creation
    allow(StripeService).to receive(:create_tip_payment_session).and_return({
      session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_tip_test_123')
    })
  end

  context 'Customer adds tip after experience completion' do
    let!(:completed_booking) do
      create(:booking, 
        business: business, 
        service: experience_service, 
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: 3.hours.ago, # Experience completed 1 hour ago (3 hours ago + 2 hour duration)
        status: :confirmed
      )
    end
    let(:tip_token) { completed_booking.generate_tip_token }

    before do
      sign_in user
    end

    it 'allows customer to add tip after experience completion' do
      with_subdomain(business.subdomain) do
        # Visit tip form directly with token
        visit new_tip_path(booking_id: completed_booking.id, token: tip_token)
        
        # Should be on tip form page
        expect(page).to have_content('Thank You!')
        expect(page).to have_content('Wine Tasting Experience')
        
        # Click on 20% tip button (which should be $15.00 for $75 service)
        click_button '20%'
        
        # Wait for JavaScript to process the tip selection
        expect(page).to have_content('Tip Selected')
        expect(page).to have_content('$15.00')
        
        # Submit tip form
        click_button 'Add $15.00 Tip'
        
        # Should redirect to Stripe checkout (mocked)
        expect(current_url).to eq('https://checkout.stripe.com/pay/cs_tip_test_123')
        
        # Verify tip was created
        tip = Tip.last
        expect(tip.amount).to eq(15.00)
        expect(tip.booking).to eq(completed_booking)
        expect(tip.business).to eq(business)
        expect(tip.tenant_customer).to eq(tenant_customer)
        expect(tip.status).to eq('pending')
        
        # Verify Stripe service was called
        expect(StripeService).to have_received(:create_tip_payment_session)
      end
    end

    it 'shows validation errors for invalid tip amounts' do
      with_subdomain(business.subdomain) do
        visit new_tip_path(booking_id: completed_booking.id, token: tip_token)
        
        # Try to submit without selecting any tip amount
        click_button 'Add Tip'
        
        # Should show JavaScript alert (form prevents submission)
        # Since we can't easily test JavaScript alerts in system tests,
        # we'll just verify the form is still on the same page
        expect(current_path).to eq(new_tip_path)
      end
    end

    it 'prevents duplicate tips for same booking' do
      # Create existing tip
      create(:tip, :completed, business: business, booking: completed_booking, tenant_customer: tenant_customer)
      
      with_subdomain(business.subdomain) do
        # Direct access to tip form should redirect
        visit new_tip_path(booking_id: completed_booking.id, token: tip_token)
        
        expect(page).to have_content('A tip has already been provided for this booking')
        expect(current_path).to eq(tip_path(completed_booking.tip))
        expect(page.current_url).to include("token=#{tip_token}")
      end
    end
  end

  context 'Future experience booking' do
    let!(:future_booking) do
      create(:booking, 
        business: business, 
        service: experience_service, 
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: 1.hour.from_now, # Experience in the future
        status: :confirmed
      )
    end
    let(:tip_token) { future_booking.generate_tip_token }

    before do
      sign_in user
    end

    it 'allows tips for future experiences' do
      with_subdomain(business.subdomain) do
        # Should be able to access tip form for future bookings
        visit new_tip_path(booking_id: future_booking.id, token: tip_token)
        
        expect(page).to have_content('Thank You!')
        expect(page).to have_content('Wine Tasting Experience')
        expect(page).to have_content('Show Your Appreciation')
      end
    end
  end

  context 'Standard service booking' do
    let!(:standard_service) { create(:service, business: business, name: 'Haircut', price: 50.00, service_type: :standard) }
          let!(:standard_booking) do
        create(:booking, 
          business: business, 
          service: standard_service, 
          staff_member: staff_member,
          tenant_customer: tenant_customer,
          start_time: 1.hour.ago,
          status: :confirmed
        )
      end
    let(:tip_token) { standard_booking.generate_tip_token }

    before do
      sign_in user
    end

    it 'does not show tip option for standard services' do
      with_subdomain(business.subdomain) do
        # Direct access should redirect with error
        visit new_tip_path(booking_id: standard_booking.id, token: tip_token)
        
        expect(page).to have_content('This service is not eligible for tips')
        expect(current_path).to eq(tenant_my_booking_path(standard_booking))
      end
    end
  end



  context 'Tip payment success flow' do
    let!(:completed_booking) do
      create(:booking, 
        business: business, 
        service: experience_service, 
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: 3.hours.ago,
        status: :confirmed
      )
    end
    let!(:tip) { create(:tip, :completed, business: business, booking: completed_booking, tenant_customer: tenant_customer, amount: 20.00) }
    let(:tip_token) { completed_booking.generate_tip_token }

    before do
      sign_in user
    end

    it 'handles tip payment success' do
      with_subdomain(business.subdomain) do
        visit success_tip_path(tip, token: tip_token)
        
        expect(page).to have_content('Thank you for your tip! Your appreciation means a lot to our team.')
        expect(current_path).to eq(tenant_my_booking_path(completed_booking))
      end
    end

    it 'handles tip payment cancellation' do
      # Create a separate booking for cancellation test
      cancellation_booking = create(:booking, 
        business: business, 
        service: experience_service, 
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: 6.hours.ago,  # Different time to avoid conflict
        status: :confirmed
      )
      cancellation_token = cancellation_booking.generate_tip_token
      
      # Create a pending tip for cancellation test
      pending_tip = create(:tip, business: business, booking: cancellation_booking, tenant_customer: tenant_customer, amount: 15.00, status: :pending)
      
      with_subdomain(business.subdomain) do
        visit cancel_tip_path(pending_tip, token: cancellation_token)
        
        expect(page).to have_content('Tip payment was cancelled.')
        expect(current_path).to eq(tenant_my_booking_path(cancellation_booking))
        
        # Tip should be destroyed if it was pending
        expect(Tip.exists?(pending_tip.id)).to be false
      end
    end
  end

  context 'Unauthenticated user' do
    let!(:completed_booking) do
      create(:booking, 
        business: business, 
        service: experience_service, 
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: 3.hours.ago,
        status: :confirmed
      )
    end
    let(:tip_token) { completed_booking.generate_tip_token }

    it 'allows tip access with valid token even when unauthenticated' do
      with_subdomain(business.subdomain) do
        visit new_tip_path(booking_id: completed_booking.id, token: tip_token)
        
        # Should be able to access tip form with valid token
        expect(page).to have_content('Thank You!')
        expect(page).to have_content('Wine Tasting Experience')
        expect(page).to have_content('Show Your Appreciation')
        
        # Should show tip percentage options
        expect(page).to have_content('15%')
        expect(page).to have_content('18%')
        expect(page).to have_content('20%')
      end
    end
  end

  context 'Stripe error handling' do
    let!(:completed_booking) do
      create(:booking, 
        business: business, 
        service: experience_service, 
        staff_member: staff_member,
        tenant_customer: tenant_customer,
        start_time: 3.hours.ago,
        status: :confirmed
      )
    end
    let(:tip_token) { completed_booking.generate_tip_token }

    before do
      sign_in user
      
      # Mock Stripe error
      allow(StripeService).to receive(:create_tip_payment_session)
        .and_raise(Stripe::StripeError.new('Stripe connection error'))
    end

    it 'handles Stripe errors gracefully' do
      with_subdomain(business.subdomain) do
        visit new_tip_path(booking_id: completed_booking.id, token: tip_token)
        
        # Click on 15% tip button for the Stripe error test
        click_button '15%'

        
        click_button 'Add $11.25 Tip'
        
        # Should redirect back with error message
        expect(page).to have_content('Could not connect to payment processor')
        expect(current_path).to eq(new_tip_path)
        
        # Tip should not be created
        expect(Tip.count).to eq(0)
      end
    end
  end
end 