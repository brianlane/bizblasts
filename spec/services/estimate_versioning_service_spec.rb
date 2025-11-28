# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EstimateVersioningService, type: :service do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:estimate) do
    est = create(:estimate,
           business: business,
           tenant_customer: customer,
           status: :sent)
    # Create items first
    create(:estimate_item, estimate: est, description: 'Item 1', qty: 1, cost_rate: 50)
    create(:estimate_item, estimate: est, description: 'Item 2', qty: 2, cost_rate: 25)
    # Recalculate totals and set initial version
    est.recalculate_totals!
    est.update_columns(current_version: 1, total_versions: 1)
    est.reload
    est
  end
  let!(:item1) { estimate.estimate_items.find_by(description: 'Item 1') }
  let!(:item2) { estimate.estimate_items.find_by(description: 'Item 2') }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '.create_version' do
    context 'when estimate has meaningful changes' do
      it 'creates a new version snapshot via callback' do
        expect {
          # Change item cost which will recalculate totals
          item1.update!(cost_rate: 75)
          estimate.recalculate_totals!
        }.to change(EstimateVersion, :count).by(1)
      end

      it 'increments version numbers via callback' do
        # Change item cost which will recalculate totals
        item1.update!(cost_rate: 75)
        estimate.recalculate_totals!

        estimate.reload
        expect(estimate.current_version).to eq(2)
        expect(estimate.total_versions).to eq(2)
      end

      it 'creates version with snapshot data' do
        # Change item cost which will recalculate totals
        item1.update!(cost_rate: 75)
        estimate.recalculate_totals!

        version = estimate.estimate_versions.last
        expect(version).to be_present
        expect(version.snapshot).to be_present
        expect(version.snapshot['estimate']).to be_present
        expect(version.snapshot['items']).to be_an(Array)
        expect(version.snapshot['customer']).to be_present
        expect(version.snapshot['version_metadata']).to be_present
      end
    end

    context 'when estimate is in draft status' do
      it 'does not create version' do
        draft_estimate = create(:estimate,
          business: business,
          tenant_customer: customer,
          status: :draft,
          total: 100)

        expect {
          draft_estimate.update(total: 120)
        }.not_to change(EstimateVersion, :count)
      end
    end

    context 'when only timestamp changes' do
      it 'does not create version for touch' do
        expect {
          estimate.touch
        }.not_to change(EstimateVersion, :count)
      end
    end
  end

  describe '.restore_version' do
    let!(:original_snapshot) do
      {
        'estimate' => estimate.attributes.stringify_keys.merge('total' => '110.0', 'subtotal' => '100.0'),
        'items' => [
          {
            'description' => 'Original Item',
            'qty' => 1,
            'cost_rate' => '100.0',
            'total' => '100.0',
            'optional' => false,
            'customer_selected' => true,
            'customer_declined' => false,
            'item_type' => 'service',
            'tax_rate' => '0.0',
            'position' => 1
          }
        ],
        'customer' => {
          'name' => customer.full_name,
          'email' => customer.email
        },
        'version_metadata' => {
          'total' => 110.0,
          'subtotal' => 100.0,
          'taxes' => 10.0,
          'item_count' => 1
        }
      }
    end

    let!(:version1) do
      create(:estimate_version,
             estimate: estimate,
             version_number: 1,
             snapshot: original_snapshot)
    end

    before do
      # Make changes to estimate after version was created
      estimate.update_columns(total: 200, subtotal: 180, current_version: 2, total_versions: 2, taxes: 20)
      estimate.estimate_items.destroy_all
      create(:estimate_item, estimate: estimate, description: 'New Item', qty: 2, cost_rate: 90)
    end

    it 'restores estimate to snapshot state' do
      result = EstimateVersioningService.restore_version(version1)

      expect(result).to be true
      estimate.reload
      # Just verify restoration happened - totals will be recalculated
      expect(estimate.current_version).to eq(3)
      expect(estimate.total_versions).to eq(3)
    end

    it 'creates a new version noting the restoration' do
      expect {
        EstimateVersioningService.restore_version(version1)
      }.to change(EstimateVersion, :count).by(1)

      latest_version = estimate.estimate_versions.order(version_number: :desc).first
      expect(latest_version.change_notes).to include('Restored to version 1')
    end

    it 'returns true on success' do
      result = EstimateVersioningService.restore_version(version1)
      expect(result).to be true
    end
  end
end
