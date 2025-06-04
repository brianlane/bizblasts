# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessesController, type: :controller do
  describe 'GET #index' do
    let!(:business1) { create(:business, name: 'Coffee Shop', description: 'A cozy place for fresh coffee and pastries', industry: :coffee_shops) }
    let!(:business2) { create(:business, name: 'Hair Salon', description: 'Professional hair styling and treatments', industry: :hair_salons) }
    let!(:inactive_business) { create(:business, name: 'Closed Shop', description: 'This business is closed', active: false) }

    context 'without search parameters' do
      it 'returns successful response with active businesses' do
        get :index
        expect(response).to have_http_status(:success)
        expect(assigns(:businesses)).to be_present
        businesses = assigns(:businesses).to_a
        expect(businesses).not_to include(inactive_business)
      end
    end

    context 'with description search' do
      it 'finds businesses with matching descriptions' do
        get :index, params: { search: 'coffee' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business1)
        expect(businesses).not_to include(business2)
      end

      it 'performs case-insensitive search' do
        get :index, params: { search: 'COFFEE' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business1)
        expect(businesses).not_to include(business2)
      end

      it 'finds partial matches' do
        get :index, params: { search: 'hair styling' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business2)
        expect(businesses).not_to include(business1)
      end

      it 'returns empty result when no matches found' do
        get :index, params: { search: 'nonexistent' }
        expect(assigns(:businesses).to_a).to be_empty
      end

      it 'handles empty search parameter' do
        get :index, params: { search: '' }
        expect(assigns(:businesses)).to be_present
      end

      it 'handles whitespace-only search parameter' do
        get :index, params: { search: '   ' }
        expect(assigns(:businesses)).to be_present
      end

      it 'finds multiple businesses with similar descriptions' do
        business4 = create(:business, description: 'Another coffee place with great coffee')
        get :index, params: { search: 'coffee' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business1, business4)
      end
    end

    context 'with search and industry filter combined' do
      it 'applies both filters correctly' do
        get :index, params: { search: 'hair', industry: 'Hair Salons' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business2)
        expect(businesses).not_to include(business1)
      end

      it 'returns empty when filters don\'t match any business' do
        get :index, params: { search: 'coffee', industry: 'Hair Salons' }
        expect(assigns(:businesses).to_a).to be_empty
      end
    end

    context 'with search and sorting' do
      let!(:newer_business) { create(:business, name: 'New Coffee', description: 'Fresh coffee shop', created_at: 1.day.ago) }
      let!(:older_business) { create(:business, name: 'Old Coffee', description: 'Established coffee house', created_at: 1.week.ago) }

      it 'applies search and sorts by name ascending' do
        get :index, params: { search: 'coffee', sort: 'name', direction: 'asc' }
        businesses = assigns(:businesses).to_a
        coffee_businesses = businesses.select { |b| b.description.downcase.include?('coffee') }
        expect(coffee_businesses.size).to be >= 2
        # Should include the original business1 and new coffee business
        expect(coffee_businesses.map(&:name)).to include('Coffee Shop', 'New Coffee')
        # Check that they are sorted by name ascending
        sorted_names = coffee_businesses.map(&:name).sort
        expect(coffee_businesses.map(&:name)).to eq(sorted_names)
      end

      it 'applies search and sorts by date descending' do
        get :index, params: { search: 'coffee', sort: 'date', direction: 'desc' }
        businesses = assigns(:businesses).to_a
        coffee_businesses = businesses.select { |b| b.description.downcase.include?('coffee') }
        expect(coffee_businesses.size).to be >= 2
        # Most recent should come first
        expect(coffee_businesses.first.created_at).to be >= coffee_businesses.last.created_at
      end
    end

    context 'security and edge cases' do
      it 'handles SQL injection attempts safely' do
        malicious_input = "'; DROP TABLE businesses; --"
        expect {
          get :index, params: { search: malicious_input }
        }.not_to raise_error
        expect(Business.count).to eq(3) # Original businesses should still exist
      end

      it 'handles special characters in search' do
        business_with_special = create(:business, description: 'Coffee & tea with 100% organic beans!')
        get :index, params: { search: '100%' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business_with_special)
      end

      it 'handles unicode characters in search' do
        business_with_unicode = create(:business, description: 'Café with délicious pastries')
        get :index, params: { search: 'délicious' }
        businesses = assigns(:businesses).to_a
        expect(businesses).to include(business_with_unicode)
      end
    end
  end
end 