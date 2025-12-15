# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::CustomersImporter do
  let(:business) { create(:business) }

  def create_import_run(csv_content)
    import_run = build(:csv_import_run, business: business, import_type: 'customers')
    import_run.csv_file.attach(
      io: StringIO.new(csv_content),
      filename: 'customers.csv',
      content_type: 'text/csv'
    )
    import_run.save!
    import_run
  end

  describe '#import' do
    context 'creating new customers' do
      it 'creates customers from CSV' do
        csv = "email,first_name,last_name\njohn@test.com,John,Doe\njane@test.com,Jane,Smith"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect { importer.import }.to change(TenantCustomer, :count).by(2)

          import_run.reload
          expect(import_run.status).to eq('succeeded')
          expect(import_run.created_count).to eq(2)
          expect(import_run.updated_count).to eq(0)
        end
      end

      it 'normalizes email to lowercase' do
        csv = "email,first_name,last_name\nJOHN@TEST.COM,John,Doe"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          importer.import
          customer = TenantCustomer.find_by(email: 'john@test.com')
          expect(customer).to be_present
        end
      end

      it 'imports optional fields' do
        csv = "email,first_name,last_name,phone,address,notes,active,phone_opt_in\njohn@test.com,John,Doe,+15551234567,123 Main St,VIP customer,true,yes"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          importer.import
          customer = TenantCustomer.find_by(email: 'john@test.com')

          expect(customer.phone).to be_present
          expect(customer.address).to eq('123 Main St')
          expect(customer.notes).to eq('VIP customer')
          expect(customer.active).to be true
          expect(customer.phone_opt_in).to be true
        end
      end
    end

    context 'updating existing customers' do
      it 'updates existing customer by email' do
        existing = create(:tenant_customer, business: business, email: 'john@test.com', first_name: 'Johnny')

        csv = "email,first_name,last_name\njohn@test.com,John,Doe"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect { importer.import }.not_to change(TenantCustomer, :count)

          import_run.reload
          expect(import_run.status).to eq('succeeded')
          expect(import_run.created_count).to eq(0)
          expect(import_run.updated_count).to eq(1)

          existing.reload
          expect(existing.first_name).to eq('John')
        end
      end

      it 'matches email case-insensitively' do
        existing = create(:tenant_customer, business: business, email: 'john@test.com', first_name: 'Johnny')

        csv = "email,first_name,last_name\nJOHN@TEST.COM,John,Doe"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          importer.import
          expect(import_run.reload.updated_count).to eq(1)
          expect(existing.reload.first_name).to eq('John')
        end
      end
    end

    context 'with validation errors' do
      it 'records error for missing email' do
        csv = "email,first_name,last_name\n,John,Doe"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          importer.import
          expect(importer.errors).to include(hash_including(message: 'Email is required'))
        end
      end

      it 'records error for invalid email format' do
        csv = "email,first_name,last_name\ninvalid-email,John,Doe"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          importer.import
          expect(importer.errors.first[:message]).to include('Invalid email format')
        end
      end

      it 'sets partial status when some rows succeed and some fail' do
        csv = "email,first_name,last_name\njohn@test.com,John,Doe\n,Jane,Smith"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          importer.import
          import_run.reload
          expect(import_run.status).to eq('partial')
          expect(import_run.created_count).to eq(1)
          expect(import_run.error_count).to eq(1)
        end
      end
    end

    context 'with mixed create and update' do
      it 'creates new and updates existing in same import' do
        existing = create(:tenant_customer, business: business, email: 'existing@test.com', first_name: 'Old')

        csv = "email,first_name,last_name\nexisting@test.com,Updated,Name\nnew@test.com,New,Person"
        import_run = create_import_run(csv)
        importer = described_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect { importer.import }.to change(TenantCustomer, :count).by(1)

          import_run.reload
          expect(import_run.created_count).to eq(1)
          expect(import_run.updated_count).to eq(1)
          expect(existing.reload.first_name).to eq('Updated')
        end
      end
    end
  end

  describe 'required_headers' do
    it 'requires email, first_name, and last_name' do
      csv = "email,first_name\njohn@test.com,John"
      import_run = create_import_run(csv)
      importer = described_class.new(business: business, import_run: import_run)

      ActsAsTenant.with_tenant(business) do
        expect(importer.import).to be false
        expect(importer.errors.first[:message]).to include('Missing required columns')
        expect(importer.errors.first[:message]).to include('last_name')
      end
    end
  end
end

