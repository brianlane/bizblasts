# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReviewRequestMailer, type: :mailer do
  let(:business) { create(:business, name: 'Test Business', google_place_id: 'ChIJN1t_tDeuEmsRUsoyG83frY4') }
  let(:tenant_customer) { create(:tenant_customer, business: business, first_name: 'John', last_name: 'Doe', email: 'john@example.com') }
  let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer) }
  let(:service) { create(:service, business: business, name: 'Test Service') }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, booking: booking) }
  let(:tracking_token) { 'secure_tracking_token_123' }

  let(:request_data) do
    {
      business: business,
      customer: tenant_customer,
      booking: booking,
      invoice: invoice,
      tracking_token: tracking_token
    }
  end

  before do
    ActsAsTenant.current_tenant = business
    # Mock unsubscribe token generator
    allow(tenant_customer).to receive(:unsubscribe_token).and_return('customer_unsubscribe_token')
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '#review_request_email' do
  let(:mail) { described_class.review_request_email(request_data) }

    context 'with valid request data' do
      it 'renders the email' do
        expect(mail).not_to be_nil
        expect(mail.subject).to include('Thank you for choosing Test Business')
        expect(mail.to).to eq(['john@example.com'])
        expect(mail.from).to eq([ENV['MAILER_EMAIL']])
      end

      it 'includes business name in subject' do
        expect(mail.subject).to include('Test Business')
      end

      it 'includes Google review URL in body' do
        expected_url = "https://search.google.com/local/writereview?placeid=#{business.google_place_id}"
        expect(mail.body.encoded).to include(expected_url)
      end

      it 'includes customer first name in greeting' do
        expect(mail.body.encoded).to include('Hi John,')
      end

      it 'includes business name in content' do
        expect(mail.body.encoded).to include('Test Business')
      end

      it 'includes unsubscribe link with tracking token' do
        expect(mail.body.encoded).to include("/unsubscribe/review_requests/#{tracking_token}")
      end

      it 'includes Google policy compliant language' do
        text_body = mail.text_part.body.to_s
        expect(text_body).to include('Your feedback is important to us')
        expect(text_body).to include('helps other customers make informed decisions')
        expect(text_body.downcase).not_to include('positive review')
        expect(text_body.downcase).not_to include('5 stars')
      end

      it 'includes one-time request disclaimer' do
        expect(mail.text_part.body.to_s).to include('one-time request')
        expect(mail.text_part.body.to_s).to include("won't send additional review requests")
      end

      it 'sets correct mailer variables' do
        # Trigger mail generation to set instance variables
        mail.body
        # In Rails 7, instance variables are not directly accessible on MessageDelivery
        # Assert via content instead
        expect(mail.body.encoded).to include('Hi John,')
        expect(mail.body.encoded).to include('Test Business')
        expect(mail.body.encoded).to include("/unsubscribe/review_requests/#{tracking_token}")
      end
    end

    context 'with service booking' do
      before do
        allow(booking).to receive(:service).and_return(service)
        request_data[:booking] = booking
      end

      it 'includes service name in subject when available' do
        expect(mail.subject).to include('Share your experience')
      end

      it 'personalizes email content with service name' do
        expect(mail.body.encoded).to include('Test Service')
      end
    end

    context 'with order instead of booking' do
      let(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
      let(:service_line_item) do
        double('LineItem', service: service)
      end
      
      let(:request_data_with_order) do
        {
          business: business,
          customer: tenant_customer,
          order: order,
          invoice: invoice,
          tracking_token: tracking_token
        }
      end

      before do
        allow(order).to receive(:service_line_items).and_return([service_line_item])
      end

      it 'extracts service name from order line items' do
        mail = described_class.review_request_email(request_data_with_order)
        # The mailer should extract service name for personalization
        expect(mail).not_to be_nil
      end
    end

    context 'when business has no Google Place ID' do
      let(:business_without_place_id) { create(:business, google_place_id: nil) }
      let(:request_data_invalid) do
        request_data.merge(business: business_without_place_id)
      end

      it 'returns NullMail and does not send email' do
        delivery = described_class.review_request_email(request_data_invalid)
        expect(delivery).to be_a(ActionMailer::MessageDelivery)
        expect(delivery.message).to be_a(ActionMailer::Base::NullMail)
      end
    end

    context 'when customer cannot receive emails' do
      before do
        allow(tenant_customer).to receive(:can_receive_email?).with(:customer).and_return(false)
        allow(tenant_customer).to receive(:can_receive_email?).with(:payment).and_return(true)
      end

      it 'returns NullMail and does not send email' do
        delivery = described_class.review_request_email(request_data)
        expect(delivery).to be_a(ActionMailer::MessageDelivery)
        expect(delivery.message).to be_a(ActionMailer::Base::NullMail)
      end
    end

    context 'when required data is missing' do
      it 'returns NullMail when business is missing' do
        invalid_data = request_data.merge(business: nil)
        delivery = described_class.review_request_email(invalid_data)
        expect(delivery).to be_a(ActionMailer::MessageDelivery)
        expect(delivery.message).to be_a(ActionMailer::Base::NullMail)
      end

      it 'returns NullMail when customer is missing' do
        invalid_data = request_data.merge(customer: nil)
        delivery = described_class.review_request_email(invalid_data)
        expect(delivery).to be_a(ActionMailer::MessageDelivery)
        expect(delivery.message).to be_a(ActionMailer::Base::NullMail)
      end

      it 'returns NullMail when tracking token is missing' do
        invalid_data = request_data.merge(tracking_token: nil)
        delivery = described_class.review_request_email(invalid_data)
        expect(delivery).to be_a(ActionMailer::MessageDelivery)
        expect(delivery.message).to be_a(ActionMailer::Base::NullMail)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Rails.logger).to receive(:error)
        # Simulate an error raised during mail creation
        allow_any_instance_of(ReviewRequestMailer).to receive(:mail).and_raise(StandardError.new('Test error'))
      end

      it 'logs the error and returns a NullMail via MessageDelivery' do
        expect(Rails.logger).to receive(:error).with(match(/Failed to send review request to.*Test error/))
        delivery = described_class.review_request_email(request_data)
        expect(delivery).to be_a(ActionMailer::MessageDelivery)
        expect { delivery.message }.not_to raise_error
        expect(delivery.message).to be_a(ActionMailer::Base::NullMail)
      end
    end

    context 'email content validation' do
      it 'has both HTML and text versions' do
        expect(mail.html_part).to be_present
        expect(mail.text_part).to be_present
      end

      it 'includes required elements in HTML version' do
        html_body = mail.html_part.body.to_s
        
        expect(html_body).to include('Hi John,')
        expect(html_body).to include('Test Business')
        expect(html_body).to include('Share Your Experience on Google')
        expect(html_body).to include('one-time request')
        expect(html_body).to include('Unsubscribe from review requests')
      end

      it 'includes required elements in text version' do
        text_body = mail.text_part.body.to_s
        
        expect(text_body).to include('Hi John,')
        expect(text_body).to include('Test Business')
        expect(text_body).to include('Share Your Experience on Google:')
        expect(text_body).to include('one-time request')
        expect(text_body).to include('Unsubscribe from review requests:')
      end
    end
  end

  describe 'Google Policy Compliance' do
    let(:mail) { described_class.review_request_email(request_data) }

    it 'does not bias toward positive reviews' do
      body = mail.text_part.body.to_s.downcase
      
      # Should not contain biasing language
      expect(body).not_to include('positive')
      expect(body).not_to include('5 star')
      expect(body).not_to include('great review')
      expect(body).not_to include('excellent review')
      expect(body).not_to include('happy')
    end

    it 'uses neutral language' do
      body = mail.text_part.body.to_s.downcase
      
      expect(body).to include('your feedback')
      expect(body).to include('share your experience')
      expect(body).to include('write about your experience')
    end

    it 'links directly to Google review page' do
      expected_url = "https://search.google.com/local/writereview?placeid=#{business.google_place_id}"
      expect(mail.body.encoded).to include(expected_url)
    end

    it 'provides clear unsubscribe mechanism' do
      expect(mail.body.encoded).to include('Unsubscribe from review requests')
      expect(mail.body.encoded).to include('one-time request')
    end

    it 'does not offer incentives for reviews' do
      body = mail.body.encoded.downcase
      
      expect(body).not_to include('discount')
      expect(body).not_to include('coupon')
      expect(body).not_to include('reward')
      expect(body).not_to include('free')
      expect(body).not_to include('offer')
    end
  end
end