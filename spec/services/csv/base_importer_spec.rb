# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::BaseImporter do
  let(:business) { create(:business) }

  # Create a concrete implementation for testing
  let(:test_importer_class) do
    Class.new(described_class) do
      def required_headers
        %w[name email]
      end

      def process_row(row, row_number)
        # Simple implementation: just count as created
        import_run.increment_progress!(created: true)
      end

      def build_attributes(row)
        { name: row['name'], email: row['email'] }
      end
    end
  end

  def create_import_run(csv_content)
    import_run = build(:csv_import_run, business: business)
    import_run.csv_file.attach(
      io: StringIO.new(csv_content),
      filename: 'test.csv',
      content_type: 'text/csv'
    )
    import_run.save!
    import_run
  end

  describe '#import' do
    context 'with valid CSV' do
      it 'processes all rows' do
        csv = "name,email\nJohn,john@test.com\nJane,jane@test.com"
        import_run = create_import_run(csv)
        importer = test_importer_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect(importer.import).to be true
          expect(import_run.reload.status).to eq('succeeded')
          expect(import_run.total_rows).to eq(2)
          expect(import_run.created_count).to eq(2)
        end
      end

      it 'handles UTF-8 BOM' do
        csv = "\xEF\xBB\xBFname,email\nJohn,john@test.com"
        import_run = create_import_run(csv)
        importer = test_importer_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect(importer.import).to be true
        end
      end
    end

    context 'with missing required headers' do
      it 'fails with error message' do
        csv = "name,phone\nJohn,555-1234"
        import_run = create_import_run(csv)
        importer = test_importer_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect(importer.import).to be false
          expect(importer.errors.first[:message]).to include('Missing required columns')
          expect(importer.errors.first[:message]).to include('email')
        end
      end
    end

    context 'with too many rows' do
      it 'fails when exceeding MAX_ROWS' do
        # Stub constant for testing
        stub_const('Csv::BaseImporter::MAX_ROWS', 2)

        csv = "name,email\nA,a@test.com\nB,b@test.com\nC,c@test.com"
        import_run = create_import_run(csv)
        importer = test_importer_class.new(business: business, import_run: import_run)

        ActsAsTenant.with_tenant(business) do
          expect(importer.import).to be false
          expect(importer.errors.first[:message]).to include('Too many rows')
        end
      end
    end

    context 'with file too large' do
      it 'fails when exceeding MAX_FILE_SIZE' do
        import_run = create_import_run("email,name\ntest@test.com,Test")
        importer = test_importer_class.new(business: business, import_run: import_run)

        # Stub the blob byte_size to be larger than max
        allow(import_run.csv_file.blob).to receive(:byte_size).and_return(15.megabytes)

        expect(importer.import).to be false
        expect(importer.errors.first[:message]).to include('File too large')
      end
    end
  end

  describe 'helper methods' do
    let(:import_run) { create(:csv_import_run, business: business) }
    let(:importer) { test_importer_class.new(business: business, import_run: import_run) }

    describe '#parse_boolean' do
      it 'returns true for truthy values' do
        %w[true yes 1 t y TRUE Yes].each do |value|
          expect(importer.send(:parse_boolean, value)).to be true
        end
      end

      it 'returns false for falsey values' do
        %w[false no 0 n FALSE No].each do |value|
          expect(importer.send(:parse_boolean, value)).to be false
        end
      end

      it 'returns default for blank value' do
        expect(importer.send(:parse_boolean, nil, default: true)).to be true
        expect(importer.send(:parse_boolean, '', default: false)).to be false
      end
    end

    describe '#parse_decimal' do
      it 'parses decimal strings' do
        expect(importer.send(:parse_decimal, '19.99')).to eq(BigDecimal('19.99'))
        expect(importer.send(:parse_decimal, '$100.50')).to eq(BigDecimal('100.50'))
      end

      it 'returns nil for blank values' do
        expect(importer.send(:parse_decimal, nil)).to be_nil
        expect(importer.send(:parse_decimal, '')).to be_nil
      end
    end

    describe '#parse_integer' do
      it 'parses integer strings' do
        expect(importer.send(:parse_integer, '42')).to eq(42)
        expect(importer.send(:parse_integer, ' 100 ')).to eq(100)
      end

      it 'returns nil for blank values' do
        expect(importer.send(:parse_integer, nil)).to be_nil
      end
    end

    describe '#parse_datetime' do
      it 'parses datetime strings' do
        expect(importer.send(:parse_datetime, '2025-01-15T10:30:00')).to be_a(Time)
      end

      it 'returns nil for blank values' do
        expect(importer.send(:parse_datetime, nil)).to be_nil
      end
    end

    describe '#parse_date' do
      it 'parses date strings' do
        expect(importer.send(:parse_date, '2025-01-15')).to eq(Date.new(2025, 1, 15))
      end

      it 'returns nil for blank values' do
        expect(importer.send(:parse_date, nil)).to be_nil
      end
    end
  end
end

