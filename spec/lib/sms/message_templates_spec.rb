require 'rails_helper'

RSpec.describe Sms::MessageTemplates do
  describe '.render' do
    let(:variables) do
      {
        business_name: 'Test Business',
        service_name: 'Hair Cut',
        date: '12/25/2023',
        time: '2:00 PM',
        customer_name: 'John Doe',
        amount: '$50.00',
        link: 'https://short.ly/abc123'
      }
    end

    context 'with valid template key' do
      it 'renders booking confirmation template' do
        result = Sms::MessageTemplates.render('booking.confirmation', variables)
        
        expect(result).to include('Test Business')
        expect(result).to include('Hair Cut')
        expect(result).to include('12/25/2023')
        expect(result).to include('2:00 PM')
        expect(result).to include('https://short.ly/abc123')
      end

      it 'renders invoice created template' do
        variables[:invoice_number] = 'INV-001'
        result = Sms::MessageTemplates.render('invoice.created', variables)
        
        expect(result).to include('INV-001')
        expect(result).to include('$50.00')
        expect(result).to include('https://short.ly/abc123')
      end
    end

    context 'with invalid template key' do
      it 'returns nil for non-existent template' do
        result = Sms::MessageTemplates.render('invalid.template', variables)
        expect(result).to be_nil
      end
    end

    context 'message length limits' do
      it 'truncates messages longer than 160 characters' do
        long_variables = variables.merge(
          service_name: 'Very Long Service Name That Goes On And On',
          business_name: 'Very Long Business Name'
        )
        
        result = Sms::MessageTemplates.render('booking.confirmation', long_variables)
        expect(result.length).to be <= 160
      end
    end
  end

  describe 'convenience methods' do
    let(:variables) { { business_name: 'Test Business', service_name: 'Hair Cut' } }

    it 'provides booking_confirmation shortcut' do
      result = Sms::MessageTemplates.booking_confirmation(variables)
      expect(result).to include('Test Business')
      expect(result).to include('Hair Cut')
    end
  end
end