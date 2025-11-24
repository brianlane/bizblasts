# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Business, 'website layout callback', type: :model do
  describe 'LAYOUT_RELATED_FIELDS constant' do
    it 'defines the fields that affect enhanced layout rendering' do
      expect(Business::LAYOUT_RELATED_FIELDS).to be_a(Array)
      expect(Business::LAYOUT_RELATED_FIELDS).to be_frozen
      expect(Business::LAYOUT_RELATED_FIELDS).to match_array([
        'website_layout',
        'name',
        'description',
        'industry',
        'city',
        'state',
        'show_services_section',
        'show_products_section',
        'enhanced_accent_color'
      ])
    end
  end

  describe 'handle_website_layout_change callback condition' do
    let(:business) { create(:business, website_layout: 'enhanced') }

    context 'when layout-related fields change' do
      it 'correctly identifies name change as layout-related' do
        business.update!(name: 'New Name')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('name')
      end

      it 'correctly identifies description change as layout-related' do
        business.update!(description: 'New description')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('description')
      end

      it 'correctly identifies industry change as layout-related' do
        business.update!(industry: 'consulting')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('industry')
      end

      it 'correctly identifies city change as layout-related' do
        business.update!(city: 'New City')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('city')
      end

      it 'correctly identifies state change as layout-related' do
        # Ensure state is different before update to guarantee a change
        business.update!(state: 'CA')
        business.reload
        business.update!(state: 'NY')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('state')
      end

      it 'correctly identifies show_services_section change as layout-related' do
        business.update!(show_services_section: false)
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('show_services_section')
      end

      it 'correctly identifies show_products_section change as layout-related' do
        business.update!(show_products_section: false)
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('show_products_section')
      end

      it 'correctly identifies enhanced_accent_color change as layout-related' do
        business.update!(enhanced_accent_color: 'emerald')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('enhanced_accent_color')
      end

      it 'correctly identifies website_layout change as layout-related' do
        business.update!(website_layout: 'basic')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to include('website_layout')
      end
    end

    context 'when non-layout-related fields change (Bug Fix: Prevent Unnecessary Reapplication)' do
      it 'does NOT identify phone change as layout-related' do
        business.update!(phone: '555-999-8888')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify email change as layout-related' do
        business.update!(email: 'new@example.com')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify address change as layout-related' do
        business.update!(address: '456 New Street')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify zip change as layout-related' do
        business.update!(zip: '10001')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify tier change as layout-related' do
        business.update!(tier: 'premium')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify sms_enabled change as layout-related' do
        business.update!(sms_enabled: true)
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify hours change as layout-related' do
        business.update!(hours: { monday: '9am-5pm' })
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify social media URL changes as layout-related' do
        business.update!(
          facebook_url: 'https://facebook.com/newpage',
          twitter_url: 'https://twitter.com/newhandle'
        )
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify domain settings changes as layout-related' do
        business.update!(
          custom_domain_owned: true,
          domain_registrar: 'GoDaddy'
        )
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'does NOT identify Stripe ID changes as layout-related' do
        business.update!(stripe_customer_id: 'cus_new123')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end
    end

    context 'edge cases' do
      it 'correctly identifies when multiple non-layout fields change' do
        business.update!(phone: '555-999-8888', email: 'new@example.com', zip: '10001')
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end

      it 'correctly identifies layout-related change when mixed with non-layout changes' do
        business.update!(name: 'New Name', phone: '555-999-8888', email: 'new@example.com')
        layout_changes = business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS
        expect(layout_changes).to eq(['name'])
      end

      it 'does NOT identify changes when only updated_at changes' do
        business.touch
        expect(business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).to be_empty
      end
    end

    context 'callback condition logic' do
      it 'verifies the callback condition returns true for layout-related changes' do
        # This documents the exact callback condition:
        # website_layout_enhanced? && (saved_changes.keys & LAYOUT_RELATED_FIELDS).any?

        business.update!(name: 'New Name')

        expect(business.website_layout_enhanced?).to be true
        expect((business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).any?).to be true
      end

      it 'verifies the callback condition returns false for non-layout changes' do
        business.update!(phone: '555-999-8888')

        expect(business.website_layout_enhanced?).to be true
        expect((business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).any?).to be false
      end

      it 'verifies the callback condition returns false when layout is basic' do
        basic_business = create(:business, website_layout: 'basic')
        basic_business.update!(name: 'New Name')

        expect(basic_business.website_layout_enhanced?).to be false
        # Even though name changed, callback should not fire because layout is basic
      end
    end

    context 'performance improvement documentation' do
      it 'documents the before/after callback condition' do
        # BEFORE (Cursor Bug): saved_changes.except('updated_at').present?
        # This triggered on EVERY field change (phone, email, tier, etc.)

        # AFTER (Fixed): (saved_changes.keys & LAYOUT_RELATED_FIELDS).any?
        # This only triggers when layout-related fields actually change

        # Verify improvement: updating phone no longer triggers callback
        business.update!(phone: '555-999-8888')
        non_layout_changes = business.saved_changes.keys - Business::LAYOUT_RELATED_FIELDS - ['updated_at']

        expect(non_layout_changes).to include('phone')
        expect((business.saved_changes.keys & Business::LAYOUT_RELATED_FIELDS).any?).to be false
      end
    end
  end
end
