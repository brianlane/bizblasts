# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "BusinessManager::Website::Sections", type: :request do
  include Rails.application.routes.url_helpers

  let!(:business) { create(:business) }
  let!(:manager) { create(:user, :manager, business: business) }
  let!(:page) { create(:page, business: business) }
  let!(:section) { create(:page_section, page: page, section_type: :gallery) }

  let(:host_params) { { host: "#{business.hostname}.lvh.me" } }

  before do
    sign_in manager
    Rails.application.routes.default_url_options[:host] = host_params[:host]
    ActsAsTenant.current_tenant = business
  end

  after do
    Rails.application.routes.default_url_options[:host] = nil
  end

  describe "POST /manage/website/pages/:page_id/sections/:id/gallery/reorder" do
    let!(:photo1) { create(:gallery_photo, owner: section, business: business, position: 1) }
    let!(:photo2) { create(:gallery_photo, owner: section, business: business, position: 2) }
    let!(:photo3) { create(:gallery_photo, owner: section, business: business, position: 3) }

    let(:reorder_url) { "/manage/website/pages/#{page.id}/sections/#{section.id}/gallery/reorder" }

    context "when photo_ids is an array" do
      it "reorders photos successfully" do
        post reorder_url,
             params: { photo_ids: [photo3.id, photo1.id, photo2.id] },
             headers: {},
             env: { 'HTTP_HOST' => host_params[:host] },
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('success')

        photo1.reload
        photo2.reload
        photo3.reload

        expect(photo3.position).to eq(1)
        expect(photo1.position).to eq(2)
        expect(photo2.position).to eq(3)
      end
    end

    context "when photo_ids is a single string value" do
      # This tests the fix for the bug where a single value would raise NoMethodError
      # because String doesn't respond to #map
      it "handles single string value without raising NoMethodError" do
        # This would previously raise: NoMethodError: undefined method `map' for an instance of String
        post reorder_url,
             params: { photo_ids: photo1.id.to_s },
             headers: {},
             env: { 'HTTP_HOST' => host_params[:host] },
             as: :json

        # The request should not crash - it may return an error because not all photos are included
        # but it should NOT raise NoMethodError
        expect(response.status).to be_in([200, 422])
      end
    end

    context "when photo_ids is nil/missing" do
      it "handles missing photo_ids parameter gracefully" do
        post reorder_url,
             params: {},
             headers: {},
             env: { 'HTTP_HOST' => host_params[:host] },
             as: :json

        # Should return error (not all photos included), not crash
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('error')
      end
    end

    context "when photo_ids is a single integer value" do
      it "handles single integer value without raising NoMethodError" do
        post reorder_url,
             params: { photo_ids: photo1.id },
             headers: {},
             env: { 'HTTP_HOST' => host_params[:host] },
             as: :json

        # The request should not crash
        expect(response.status).to be_in([200, 422])
      end
    end
  end
end

