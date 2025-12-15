# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvImportRun, type: :model do
  let(:business) { create(:business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:business_id) }
    it { is_expected.to validate_presence_of(:import_type) }
    it { is_expected.to validate_inclusion_of(:import_type).in_array(CsvImportRun::IMPORT_TYPES) }
  end

  describe 'IMPORT_TYPES' do
    it 'includes all expected types' do
      expect(CsvImportRun::IMPORT_TYPES).to contain_exactly(
        'customers', 'bookings', 'invoices', 'orders',
        'payments', 'products', 'services', 'customer_subscriptions'
      )
    end
  end

  describe 'status enum' do
    it 'has expected statuses' do
      expect(CsvImportRun.statuses).to eq(
        'queued' => 0,
        'running' => 1,
        'succeeded' => 2,
        'failed' => 3,
        'partial' => 4
      )
    end
  end

  describe '#start!' do
    it 'sets status to running and started_at' do
      import_run = create(:csv_import_run, business: business)
      freeze_time do
        import_run.start!
        expect(import_run.status).to eq('running')
        expect(import_run.started_at).to eq(Time.current)
      end
    end
  end

  describe '#succeed!' do
    it 'sets status to succeeded with summary' do
      import_run = create(:csv_import_run, :running, business: business)
      summary = { total_rows: 10, created: 5, updated: 5 }

      freeze_time do
        import_run.succeed!(summary: summary)
        expect(import_run.status).to eq('succeeded')
        expect(import_run.finished_at).to eq(Time.current)
        expect(import_run.summary).to eq(summary.stringify_keys)
      end
    end
  end

  describe '#fail!' do
    it 'sets status to failed with error report' do
      import_run = create(:csv_import_run, :running, business: business)
      error_report = { errors: [{ row: 1, message: 'Invalid data' }] }

      freeze_time do
        import_run.fail!(error_report: error_report)
        expect(import_run.status).to eq('failed')
        expect(import_run.finished_at).to eq(Time.current)
        expect(import_run.error_report).to eq(error_report.deep_stringify_keys)
      end
    end
  end

  describe '#partial!' do
    it 'sets status to partial with summary and errors' do
      import_run = create(:csv_import_run, :running, business: business)
      summary = { total_rows: 10, created: 5 }
      error_report = { errors: [{ row: 3, message: 'Validation failed' }] }

      freeze_time do
        import_run.partial!(summary: summary, error_report: error_report)
        expect(import_run.status).to eq('partial')
        expect(import_run.finished_at).to eq(Time.current)
        expect(import_run.summary).to eq(summary.stringify_keys)
        expect(import_run.error_report).to eq(error_report.deep_stringify_keys)
      end
    end
  end

  describe '#progress_percentage' do
    it 'returns 0 when total_rows is zero' do
      import_run = build(:csv_import_run, total_rows: 0, processed_rows: 0)
      expect(import_run.progress_percentage).to eq(0)
    end

    it 'calculates percentage correctly' do
      import_run = build(:csv_import_run, total_rows: 100, processed_rows: 50)
      expect(import_run.progress_percentage).to eq(50)
    end

    it 'rounds to nearest integer' do
      import_run = build(:csv_import_run, total_rows: 3, processed_rows: 1)
      expect(import_run.progress_percentage).to eq(33)
    end
  end

  describe '#increment_progress!' do
    it 'increments processed_rows' do
      import_run = create(:csv_import_run, :running, business: business, processed_rows: 5)
      expect { import_run.increment_progress! }.to change { import_run.reload.processed_rows }.by(1)
    end

    it 'increments created_count when created: true' do
      import_run = create(:csv_import_run, :running, business: business, created_count: 2)
      expect { import_run.increment_progress!(created: true) }.to change { import_run.reload.created_count }.by(1)
    end

    it 'increments updated_count when updated: true' do
      import_run = create(:csv_import_run, :running, business: business, updated_count: 1)
      expect { import_run.increment_progress!(updated: true) }.to change { import_run.reload.updated_count }.by(1)
    end

    it 'increments error_count when error: true' do
      import_run = create(:csv_import_run, :running, business: business, error_count: 0)
      expect { import_run.increment_progress!(error: true) }.to change { import_run.reload.error_count }.by(1)
    end
  end

  describe 'acts_as_tenant' do
    it 'scopes to current tenant' do
      other_business = create(:business)
      run1 = create(:csv_import_run, business: business)
      run2 = create(:csv_import_run, business: other_business)

      ActsAsTenant.with_tenant(business) do
        expect(CsvImportRun.all).to include(run1)
        expect(CsvImportRun.all).not_to include(run2)
      end
    end
  end
end

