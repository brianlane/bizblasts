# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClickEvent, type: :model do
  let(:business) { create(:business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:target).optional }
    it { is_expected.to belong_to(:visitor_session).optional }
  end

  describe 'validations' do
    subject { build(:click_event, business: business) }

    it { is_expected.to validate_presence_of(:visitor_fingerprint) }
    it { is_expected.to validate_presence_of(:session_id) }
    it { is_expected.to validate_presence_of(:element_type) }
    it { is_expected.to validate_presence_of(:page_path) }
  end

  describe 'enums' do
    it 'defines element_type enum' do
      expect(described_class.element_types).to include(
        'button' => 'button',
        'link' => 'link',
        'cta' => 'cta',
        'form_submit' => 'form_submit',
        'other' => 'other'
      )
    end

    it 'defines category enum' do
      expect(described_class.categories).to include(
        'booking' => 'booking',
        'product' => 'product',
        'service' => 'service',
        'contact' => 'contact',
        'navigation' => 'navigation'
      )
    end

    it 'defines action enum' do
      expect(described_class.actions).to include(
        'click' => 'click',
        'book' => 'book',
        'submit' => 'submit',
        'add_to_cart' => 'add_to_cart'
      )
    end
  end

  describe 'scopes' do
    describe '.for_period' do
      let!(:old_click) { create(:click_event, business: business, created_at: 60.days.ago) }
      let!(:recent_click) { create(:click_event, business: business, created_at: 5.days.ago) }

      it 'returns clicks within the date range' do
        result = described_class.for_period(30.days.ago, Time.current)
        expect(result).to include(recent_click)
        expect(result).not_to include(old_click)
      end
    end

    describe '.conversions' do
      let!(:conversion) { create(:click_event, :conversion, business: business) }
      let!(:regular_click) { create(:click_event, business: business) }

      it 'returns only conversion clicks' do
        result = described_class.conversions
        expect(result).to include(conversion)
        expect(result).not_to include(regular_click)
      end
    end

    describe '.booking_clicks' do
      let!(:booking_click) { create(:click_event, business: business, category: 'booking') }
      let!(:product_click) { create(:click_event, business: business, category: 'product') }

      it 'returns only booking category clicks' do
        result = described_class.booking_clicks
        expect(result).to include(booking_click)
        expect(result).not_to include(product_click)
      end
    end

    describe '.product_clicks' do
      let!(:product_click) { create(:click_event, business: business, category: 'product') }
      let!(:service_click) { create(:click_event, business: business, category: 'service') }

      it 'returns only product category clicks' do
        result = described_class.product_clicks
        expect(result).to include(product_click)
        expect(result).not_to include(service_click)
      end
    end
  end

  describe 'class methods' do
    describe '.total_clicks' do
      before do
        create_list(:click_event, 3, business: business, created_at: 5.days.ago)
        create(:click_event, business: business, created_at: 60.days.ago)
      end

      it 'counts clicks within date range' do
        expect(described_class.total_clicks(start_date: 30.days.ago, end_date: Time.current)).to eq(3)
      end
    end

    describe '.conversion_count' do
      before do
        2.times { create(:click_event, :conversion, business: business, created_at: 5.days.ago) }
        create(:click_event, business: business, created_at: 5.days.ago)
      end

      it 'counts only conversions' do
        expect(described_class.conversion_count(start_date: 30.days.ago, end_date: Time.current)).to eq(2)
      end
    end

    describe '.conversion_rate' do
      before do
        2.times { create(:click_event, :conversion, business: business, created_at: 5.days.ago) }
        create_list(:click_event, 8, business: business, created_at: 5.days.ago)
      end

      it 'calculates conversion rate percentage' do
        rate = described_class.conversion_rate(start_date: 30.days.ago, end_date: Time.current)
        expect(rate).to eq(20.0) # 2 conversions out of 10 total clicks
      end
    end

    describe '.total_conversion_value' do
      before do
        create(:click_event, :conversion, business: business, conversion_value: 100, created_at: 5.days.ago)
        create(:click_event, :conversion, business: business, conversion_value: 50, created_at: 5.days.ago)
      end

      it 'sums conversion values' do
        total = described_class.total_conversion_value(start_date: 30.days.ago, end_date: Time.current)
        expect(total).to eq(150)
      end
    end

    describe '.clicks_by_category' do
      before do
        create_list(:click_event, 3, business: business, category: 'booking', created_at: 5.days.ago)
        create_list(:click_event, 2, business: business, category: 'product', created_at: 5.days.ago)
      end

      it 'groups clicks by category' do
        result = described_class.clicks_by_category(start_date: 30.days.ago, end_date: Time.current)
        expect(result['booking']).to eq(3)
        expect(result['product']).to eq(2)
      end
    end

    describe '.top_clicked_elements' do
      before do
        create_list(:click_event, 5, business: business, element_identifier: 'book-now-btn', element_text: 'Book Now', created_at: 5.days.ago)
        create_list(:click_event, 3, business: business, element_identifier: 'contact-btn', element_text: 'Contact Us', created_at: 5.days.ago)
      end

      it 'returns top clicked elements ordered by count' do
        result = described_class.top_clicked_elements(start_date: 30.days.ago, end_date: Time.current, limit: 2)
        expect(result.keys.first).to eq(['book-now-btn', 'Book Now'])
        expect(result.values.first).to eq(5)
      end
    end

    describe '.conversion_funnel' do
      before do
        create_list(:click_event, 10, business: business, created_at: 5.days.ago)
        create_list(:click_event, 5, business: business, category: 'service', created_at: 5.days.ago)
        create_list(:click_event, 3, business: business, conversion_type: 'booking_started', created_at: 5.days.ago)
        create_list(:click_event, 1, business: business, conversion_type: 'booking_completed', created_at: 5.days.ago)
      end

      it 'returns funnel metrics' do
        result = described_class.conversion_funnel(start_date: 30.days.ago, end_date: Time.current)
        expect(result[:total_clicks]).to eq(19) # 10 + 5 + 3 + 1
        expect(result[:service_clicks]).to eq(5)
        expect(result[:booking_started]).to eq(3)
        expect(result[:booking_completed]).to eq(1)
      end
    end

    describe '.daily_trend' do
      before do
        create(:click_event, business: business, created_at: 3.days.ago)
        create_list(:click_event, 2, business: business, created_at: 2.days.ago)
        create_list(:click_event, 3, business: business, created_at: 1.day.ago)
      end

      it 'returns daily click counts' do
        result = described_class.daily_trend(start_date: 7.days.ago, end_date: Time.current)
        expect(result[3.days.ago.to_date]).to eq(1)
        expect(result[2.days.ago.to_date]).to eq(2)
        expect(result[1.day.ago.to_date]).to eq(3)
      end
    end
  end

  describe 'instance methods' do
    describe '#mark_as_conversion!' do
      let(:click) { create(:click_event, business: business) }

      it 'marks click as conversion' do
        click.mark_as_conversion!('booking_completed', 150.00)

        click.reload
        expect(click.is_conversion).to be true
        expect(click.conversion_type).to eq('booking_completed')
        expect(click.conversion_value).to eq(150.00)
      end
    end
  end

  describe 'tenant scoping' do
    let(:other_business) { create(:business) }
    let!(:click1) { create(:click_event, business: business) }
    let!(:click2) { create(:click_event, business: other_business) }

    it 'scopes clicks to current tenant' do
      ActsAsTenant.with_tenant(business) do
        expect(described_class.all).to include(click1)
        expect(described_class.all).not_to include(click2)
      end
    end
  end

  describe 'ransackable attributes' do
    it 'includes expected searchable attributes' do
      attributes = described_class.ransackable_attributes
      expect(attributes).to include('category', 'action', 'is_conversion', 'conversion_type')
    end
  end

  describe 'factory' do
    it 'creates a valid click event' do
      click = build(:click_event, business: business)
      expect(click).to be_valid
    end

    it 'creates a conversion click event with trait' do
      click = create(:click_event, :conversion, business: business)
      expect(click.is_conversion).to be true
      expect(click.conversion_value).to be_present
    end
  end
end
