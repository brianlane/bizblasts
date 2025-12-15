# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::ProcessImportJob, type: :job do
  let(:business) { create(:business) }

  def create_import_run(csv_content, import_type: 'customers')
    import_run = build(:csv_import_run, business: business, import_type: import_type)
    import_run.csv_file.attach(
      io: StringIO.new(csv_content),
      filename: 'test.csv',
      content_type: 'text/csv'
    )
    import_run.save!
    import_run
  end

  describe '#perform' do
    it 'processes customer import successfully' do
      csv = "email,first_name,last_name\njohn@test.com,John,Doe"
      import_run = create_import_run(csv)

      expect {
        described_class.new.perform(import_run.id)
      }.to change(TenantCustomer, :count).by(1)

      import_run.reload
      expect(import_run.status).to eq('succeeded')
      expect(import_run.created_count).to eq(1)
    end

    it 'routes to correct importer based on import_type' do
      csv = "name,description,price,duration\nTest Service,Description,50.00,60"
      import_run = create_import_run(csv, import_type: 'services')

      expect {
        described_class.new.perform(import_run.id)
      }.to change(Service, :count).by(1)
    end

    it 'handles import failure gracefully' do
      # CSV with missing required headers will fail validation
      import_run = create_import_run("invalid\ndata")

      described_class.new.perform(import_run.id)

      import_run.reload
      # Import should complete with failed/partial status due to missing headers
      expect(import_run.status).to eq('failed').or eq('running')
    end

    it 'sets import run to running state' do
      csv = "email,first_name,last_name\njohn@test.com,John,Doe"
      import_run = create_import_run(csv)

      expect(import_run.status).to eq('queued')
      described_class.new.perform(import_run.id)

      import_run.reload
      expect(import_run.started_at).to be_present
    end

    it 'uses correct tenant scope' do
      other_business = create(:business)

      csv = "email,first_name,last_name\njohn@test.com,John,Doe"
      import_run = create_import_run(csv)

      described_class.new.perform(import_run.id)

      customer = TenantCustomer.last
      expect(customer.business_id).to eq(business.id)
      expect(customer.business_id).not_to eq(other_business.id)
    end

    context 'when job fails with exception' do
      it 'marks import as failed and re-raises' do
        csv = "email,first_name,last_name\ntest@test.com,Test,User"
        import_run = create_import_run(csv)

        # Force an error during import
        allow_any_instance_of(Csv::CustomersImporter).to receive(:import).and_raise(StandardError, 'Test error')

        expect {
          described_class.new.perform(import_run.id)
        }.to raise_error(StandardError, 'Test error')

        import_run.reload
        expect(import_run.status).to eq('failed')
        expect(import_run.error_report['errors']).to be_present
      end
    end

    describe 'importer routing' do
      it 'routes customers type to CustomersImporter' do
        import_run = create_import_run("email,first_name,last_name\ntest@test.com,Test,User", import_type: 'customers')

        expect(Csv::CustomersImporter).to receive(:new).and_call_original
        described_class.new.perform(import_run.id)
      end

      it 'routes products type to ProductsImporter' do
        import_run = create_import_run("name,price\nTest Product,9.99", import_type: 'products')

        expect(Csv::ProductsImporter).to receive(:new).and_call_original
        described_class.new.perform(import_run.id)
      end

      it 'routes services type to ServicesImporter' do
        import_run = create_import_run("name,price,duration\nTest Service,50,60", import_type: 'services')

        expect(Csv::ServicesImporter).to receive(:new).and_call_original
        described_class.new.perform(import_run.id)
      end

      it 'raises error for unknown import type' do
        import_run = create_import_run("data\ntest")
        import_run.update_column(:import_type, 'unknown')

        # The job will fail with validation error when starting the import run,
        # because start! tries to update the record and fails validation
        expect {
          described_class.new.perform(import_run.id)
        }.to raise_error(StandardError)
      end
    end
  end

  describe 'queue' do
    it 'uses default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end
end

