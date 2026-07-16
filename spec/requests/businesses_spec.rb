# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Businesses", type: :request do
  describe "GET /businesses" do
    let!(:coffee_business) { create(:business, name: 'Local Coffee', description: 'Fresh roasted coffee beans and espresso drinks') }
    let!(:salon_business) { create(:business, name: 'Hair Studio', description: 'Professional hair styling and color treatments') }
    let!(:yoga_business) { create(:business, name: 'Zen Yoga', description: 'Peaceful yoga classes for mind and body wellness') }

    context "without search parameters" do
      it "returns successful response" do
        get businesses_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Businesses')
      end
    end

    context "with description search" do
      it "returns businesses matching search term" do
        get businesses_path, params: { search: 'coffee' }
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Local Coffee')
        expect(response.body).not_to include('Hair Studio')
        expect(response.body).not_to include('Zen Yoga')
      end

      it "shows search result count" do
        get businesses_path, params: { search: 'coffee' }
        expect(response.body).to include('found matching "coffee"')
      end

      it "shows no results message when no matches" do
        get businesses_path, params: { search: 'nonexistent' }
        expect(response).to have_http_status(:success)
        expect(response.body).to include('No businesses found with descriptions matching "nonexistent"')
        expect(response.body).to include('Reset search')
      end

      it "maintains search term in form field" do
        get businesses_path, params: { search: 'coffee' }
        expect(response.body).to include('value="coffee"')
      end
    end

    context "with combined search and filters" do
      it "applies both search and industry filter" do
        get businesses_path, params: { search: 'hair', industry: 'Hair Salons' }
        expect(response).to have_http_status(:success)
        # The response should show the no results message since the factory business has industry 'other'
        expect(response.body).to include('No businesses found with descriptions matching "hair"')
      end

      it "maintains both parameters in form" do
        get businesses_path, params: { search: 'hair', industry: 'Hair Salons' }
        expect(response.body).to include('value="hair"')
        expect(response.body).to include('value="Hair Salons"')
      end
    end

    context "form interactions" do
      it "includes search form with proper fields" do
        get businesses_path
        expect(response).to have_http_status(:success)
        expect(response.body).to include('🔍 Search Description')
        expect(response.body).to include('🏢 Filter by Industry')
        expect(response.body).to include('name="search"')
        expect(response.body).to include('name="industry"')
      end

      it "includes reset link that clears search" do
        get businesses_path, params: { search: 'coffee' }
        expect(response.body).to include('href="/businesses"')
        expect(response.body).to include('Reset')
      end
    end

    context "with many businesses" do
      before do
        # Create 20 additional businesses with deterministic descriptions
        # (10 match "coffee", 10 don't).
        20.times do |i|
          service = i.even? ? 'coffee' : 'yoga'
          create(:business,
                 name: "Business #{i}",
                 description: "This is business #{i} offering #{service} services")
        end
      end

      # NOTE: This example previously asserted the request completed in under
      # 1 wall-clock second, which flaked on shared CI runners. Response-time
      # coverage lives in the dedicated performance_test CI job; here we only
      # verify search correctness against a larger dataset.
      it "handles large dataset search correctly" do
        get businesses_path, params: { search: 'coffee' }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Local Coffee')
        expect(response.body).to include('Business 18') # coffee description
        expect(response.body).not_to include('Business 19') # yoga description
        expect(response.body).not_to include('Zen Yoga')
      end
    end
  end
end 