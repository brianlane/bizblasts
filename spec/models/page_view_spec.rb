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

    it 'requires visitor_fingerprint to be a valid hex string' do
      page_view = build(:page_view, business: business, visitor_fingerprint: 'invalid!')
      expect(page_view).not_to be_valid
      expect(page_view.errors[:visitor_fingerprint]).to include('must be a valid hexadecimal string (8-32 characters)')
    end

    it 'requires visitor_fingerprint to be at least 8 characters' do
      page_view = build(:page_view, business: business, visitor_fingerprint: 'abc123')
      expect(page_view).not_to be_valid
    end

    it 'accepts valid hex fingerprints' do
      page_view = build(:page_view, business: business, visitor_fingerprint: 'a1b2c3d4e5f60001')
      expect(page_view).to be_valid
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
    let(:fingerprint_1) { 'a1b2c3d4e5f60001' }
    let(:fingerprint_2) { 'a1b2c3d4e5f60002' }

    before do
      3.times { create(:page_view, business: business, visitor_fingerprint: fingerprint_1) }
      2.times { create(:page_view, business: business, visitor_fingerprint: fingerprint_2) }
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

