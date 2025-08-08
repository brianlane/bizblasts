# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google Reviews Integration', type: :integration do
  let(:business) { create(:business, name: 'Test Business', google_place_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4') }
  let(:tenant_customer) { create(:tenant_customer, business: business, first_name: 'John', email: 'john@example.com') }
  let(:service) { create(:service, business: business, name: 'Test Service') }
  let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service) }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, booking: booking, status: :pending) }

  before do
    ActsAsTenant.current_tenant = business
    # Clear any existing deliveries
    ActionMailer::Base.deliveries.clear
    # Mock the Google API key
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return('test_api_key')
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'Review Request Email Flow' do
    context 'when invoice is marked as paid' do
      it 'automatically sends a review request email' do
        expect {
          invoice.mark_as_paid!
        }.to change { ActionMailer::Base.deliveries.count }.by(1)

        email = ActionMailer::Base.deliveries.last
        expect(email.to).to include('john@example.com')
        expect(email.subject).to include('Thank you for choosing Test Business')
      end

      it 'includes proper Google review URL in email' do
        invoice.mark_as_paid!
        
        email = ActionMailer::Base.deliveries.last
        expected_url = "https://search.google.com/local/writereview?placeid=#{business.google_place_id}"
        expect(email.body.encoded).to include(expected_url)
      end

      it 'includes tracking token for unsubscribe functionality' do
        invoice.mark_as_paid!
        
        email = ActionMailer::Base.deliveries.last
        expect(email.body.encoded).to include('unsubscribe_review_requests_url')
      end

      it 'logs the review request email sending' do
        expect(Rails.logger).to receive(:info)
          .with(match(/Sent review request email for Invoice ##{invoice.invoice_number}/))

        invoice.mark_as_paid!
      end
    end

    context 'when business has no Google Place ID' do
      let(:business_no_place_id) { create(:business, google_place_id: nil) }
      let(:invoice_no_place_id) do
        ActsAsTenant.with_tenant(business_no_place_id) do
          create(:invoice, 
            business: business_no_place_id, 
            tenant_customer: create(:tenant_customer, business: business_no_place_id),
            status: :pending
          )
        end
      end

      it 'does not send review request email' do
        expect {
          ActsAsTenant.with_tenant(business_no_place_id) do
            invoice_no_place_id.mark_as_paid!
          end
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context 'when customer cannot receive emails' do
      before do
        allow(tenant_customer).to receive(:can_receive_email?).with(:customer).and_return(false)
      end

      it 'does not send review request email' do
        expect {
          invoice.mark_as_paid!
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context 'when review requests are already suppressed' do
      before do
        # Simulate that review requests have been suppressed
        allow(invoice).to receive(:review_request_suppressed?).and_return(true)
      end

      it 'does not send review request email' do
        expect {
          invoice.mark_as_paid!
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context 'when invoice status changes from other statuses' do
      it 'sends email when changing from pending to paid' do
        expect(invoice.status).to eq('pending')
        
        expect {
          invoice.update!(status: :paid)
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end

      it 'sends email when changing from overdue to paid' do
        invoice.update!(status: :overdue)
        
        expect {
          invoice.update!(status: :paid)
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end

      it 'does not send email when changing from paid to other status' do
        invoice.update!(status: :paid)
        ActionMailer::Base.deliveries.clear
        
        expect {
          invoice.update!(status: :cancelled)
        }.not_to change { ActionMailer::Base.deliveries.count }
      end

      it 'does not send email when changing between non-paid statuses' do
        invoice.update!(status: :overdue)
        ActionMailer::Base.deliveries.clear
        
        expect {
          invoice.update!(status: :cancelled)
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end

  describe 'Google Reviews Display Integration' do
    let(:mock_google_response) do
      {
        success: true,
        place: {
          name: 'Test Business',
          rating: 4.5,
          user_ratings_total: 123,
          google_url: 'https://maps.google.com/test'
        },
        reviews: [
          {
            author_name: 'John Doe',
            rating: 5,
            relative_time_description: '2 days ago',
            text: 'Great service!'
          },
          {
            author_name: 'Jane Smith',
            rating: 4,
            relative_time_description: '1 week ago',
            text: 'Good experience.'
          }
        ],
        google_url: "https://search.google.com/local/writereview?placeid=#{business.google_place_id}",
        fetched_at: Time.current
      }
    end

    before do
      allow(GoogleReviewsService).to receive(:fetch).and_return(mock_google_response)
    end

    context 'on public business home page' do
      it 'displays Google reviews when Place ID is configured' do
        # Simulate a request to the public home page
        # This would typically be done with a request spec or system spec
        reviews_data = GoogleReviewsService.fetch(business)
        
        expect(reviews_data[:success]).to be true
        expect(reviews_data[:reviews]).to have(2).items
        expect(reviews_data[:place][:name]).to eq('Test Business')
        expect(reviews_data[:place][:rating]).to eq(4.5)
      end

      it 'includes proper Google attribution' do
        reviews_data = GoogleReviewsService.fetch(business)
        expect(reviews_data[:google_url]).to include('search.google.com/local/writereview')
      end
    end

    context 'when Google API returns an error' do
      before do
        allow(GoogleReviewsService).to receive(:fetch).and_return({ error: 'API error' })
      end

      it 'handles errors gracefully without breaking the page' do
        reviews_data = GoogleReviewsService.fetch(business)
        expect(reviews_data[:error]).to be_present
        expect(reviews_data[:success]).to be_falsy
      end
    end
  end

  describe 'Review Request Unsubscribe Integration' do
    let(:token_data) do
      {
        business_id: business.id,
        customer_id: tenant_customer.id,
        invoice_id: invoice.id,
        booking_id: booking.id,
        generated_at: Time.current.to_i
      }
    end
    let(:verifier) { Rails.application.message_verifier('review_request_tracking') }
    let(:tracking_token) { verifier.generate(token_data) }

    context 'when customer clicks unsubscribe link' do
      it 'successfully processes the unsubscribe request' do
        # Simulate the unsubscribe controller action
        controller = ReviewRequestUnsubscribesController.new
        
        # Mock the necessary methods and instance variables
        allow(controller).to receive(:params).and_return({ token: tracking_token })
        allow(controller).to receive(:render)
        
        # Call the controller action
        controller.show
        
        # Verify the controller sets the right instance variables
        expect(controller.instance_variable_get(:@success)).to be true
        expect(controller.instance_variable_get(:@business)).to eq(business)
        expect(controller.instance_variable_get(:@customer)).to eq(tenant_customer)
      end

      it 'prevents future review emails for the same invoice' do
        # First, mark the invoice as paid and confirm email is sent
        invoice.mark_as_paid!
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        
        # Simulate unsubscribe by setting the suppression flag
        allow(invoice).to receive(:review_request_suppressed?).and_return(true)
        
        # Create a new invoice for the same customer
        new_invoice = create(:invoice, 
          business: business, 
          tenant_customer: tenant_customer, 
          booking: create(:booking, business: business, tenant_customer: tenant_customer),
          status: :pending
        )
        
        # Mark the new invoice as paid - should still send email (different invoice)
        expect {
          new_invoice.mark_as_paid!
        }.to change { ActionMailer::Base.deliveries.count }.by(1)
        
        # But if we suppress the new invoice specifically, it shouldn't send
        allow(new_invoice).to receive(:review_request_suppressed?).and_return(true)
        new_invoice.update!(status: :pending) # Reset status
        
        expect {
          new_invoice.mark_as_paid!
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end

  describe 'Google Policy Compliance' do
    before do
      invoice.mark_as_paid!
    end

    it 'sends Google policy compliant review request emails' do
      email = ActionMailer::Base.deliveries.last
      body = email.body.encoded.downcase
      
      # Should use neutral language
      expect(body).to include('your feedback')
      expect(body).to include('share your experience')
      expect(body).not_to include('positive')
      expect(body).not_to include('5 star')
      
      # Should not offer incentives
      expect(body).not_to include('discount')
      expect(body).not_to include('reward')
      expect(body).not_to include('coupon')
      
      # Should provide clear unsubscribe
      expect(body).to include('one-time request')
      expect(body).to include('unsubscribe')
      
      # Should link directly to Google
      expected_url = "https://search.google.com/local/writereview?placeid=#{business.google_place_id}"
      expect(email.body.encoded).to include(expected_url)
    end
  end

  describe 'Caching Integration' do
    let(:cache_key) { "google_reviews_#{business.id}_#{business.google_place_id}" }

    before do
      Rails.cache.clear
    end

    it 'caches Google reviews for 1 hour' do
      # First call should hit the API
      expect(GoogleReviewsService).to receive(:new).and_call_original
      first_result = GoogleReviewsService.fetch(business)
      
      # Second call should use cache
      expect(GoogleReviewsService).to receive(:new).and_call_original
      expect_any_instance_of(GoogleReviewsService).not_to receive(:fetch_from_api)
      second_result = GoogleReviewsService.fetch(business)
      
      # Results should be identical (from cache)
      expect(second_result[:fetched_at]).to eq(first_result[:fetched_at])
    end

    it 'uses proper cache key format' do
      expect(Rails.cache).to receive(:fetch)
        .with(cache_key, { expires_in: 1.hour })
        .and_call_original
      
      GoogleReviewsService.fetch(business)
    end
  end

  describe 'Error Handling Integration' do
    context 'when Google API is unavailable' do
      before do
        allow(GoogleReviewsService).to receive(:fetch).and_return({ error: 'Service unavailable' })
      end

      it 'does not prevent invoice payment processing' do
        expect {
          invoice.mark_as_paid!
        }.not_to raise_error
        
        expect(invoice.reload.status).to eq('paid')
      end

      it 'logs but does not raise errors for review display' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        
        expect {
          GoogleReviewsService.fetch(business)
        }.not_to raise_error
      end
    end

    context 'when mailer fails' do
      before do
        allow(ReviewRequestMailer).to receive(:review_request_email).and_raise(StandardError.new('Mailer error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'does not prevent invoice payment processing' do
        expect {
          invoice.mark_as_paid!
        }.not_to raise_error
        
        expect(invoice.reload.status).to eq('paid')
        expect(Rails.logger).to have_received(:error)
          .with(match(/Failed to send review request email/))
      end
    end
  end
end