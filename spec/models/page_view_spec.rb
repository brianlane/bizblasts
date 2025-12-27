# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageView, type: :model do
  let(:business) { create(:business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'validations' do
    it 'requires visitor_fingerprint' do
      page_view = build(:page_view, business: business, visitor_fingerprint: nil)
      expect(page_view).not_to be_valid
      expect(page_view.errors[:visitor_fingerprint]).to be_present
    end

    it 'requires session_id' do
      page_view = build(:page_view, business: business, session_id: nil)
      expect(page_view).not_to be_valid
      expect(page_view.errors[:session_id]).to be_present
    end

    it 'requires page_path' do
      page_view = build(:page_view, business: business, page_path: nil)
      expect(page_view).not_to be_valid
      expect(page_view.errors[:page_path]).to be_present
    end

    it 'is valid with required attributes' do
      page_view = build(:page_view, business: business)
      expect(page_view).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to a business' do
      page_view = create(:page_view, business: business)
      expect(page_view.business).to eq(business)
    end

    it 'optionally belongs to a page' do
      page = create(:page, business: business)
      page_view = create(:page_view, business: business, page: page)
      expect(page_view.page).to eq(page)
    end
  end

  describe 'scopes' do
    before do
      create(:page_view, business: business, created_at: 2.days.ago)
      create(:page_view, business: business, created_at: 10.days.ago)
      create(:page_view, business: business, created_at: 45.days.ago)
    end

    it 'filters by last_7_days' do
      expect(PageView.last_7_days.count).to eq(1)
    end

    it 'filters by last_30_days' do
      expect(PageView.last_30_days.count).to eq(2)
    end

    it 'filters by for_period' do
      expect(PageView.for_period(15.days.ago, Time.current).count).to eq(2)
    end
  end

  describe 'class methods' do
    before do
      3.times { create(:page_view, business: business, visitor_fingerprint: 'visitor1') }
      2.times { create(:page_view, business: business, visitor_fingerprint: 'visitor2') }
    end

    describe '.unique_visitors' do
      it 'returns count of distinct visitors' do
        expect(PageView.unique_visitors).to eq(2)
      end
    end

    describe '.total_page_views' do
      it 'returns total count of page views' do
        expect(PageView.total_page_views).to eq(5)
      end
    end

    describe '.top_pages' do
      it 'returns pages ordered by view count' do
        # Clear existing and create fresh data
        PageView.delete_all
        
        3.times { create(:page_view, business: business, page_path: '/services') }
        1.times { create(:page_view, business: business, page_path: '/contact') }
        
        top_pages = PageView.top_pages(limit: 10)
        # Most views should be first
        expect(top_pages.keys.first).to eq('/services')
      end
    end
  end
end

