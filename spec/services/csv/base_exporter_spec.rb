# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Csv::BaseExporter do
  let(:business) { create(:business) }

  # Create a concrete implementation for testing the base class
  let(:test_exporter_class) do
    Class.new(described_class) do
      def headers
        %w[id name value]
      end

      def row_for(record)
        [record.id, record.name, record.email]
      end

      def default_records
        business.tenant_customers.order(:id)
      end

      def export_name
        'test-export'
      end
    end
  end

  describe '#export' do
    it 'generates CSV with headers and data rows' do
      customer = create(:tenant_customer, business: business, first_name: 'John', last_name: 'Doe')
      exporter = test_exporter_class.new(business: business)

      csv = exporter.export
      lines = CSV.parse(csv)

      expect(lines.first).to eq(%w[id name value])
      expect(lines.length).to be >= 2
    end

    it 'uses custom records when provided' do
      customer1 = create(:tenant_customer, business: business)
      customer2 = create(:tenant_customer, business: business)

      records = business.tenant_customers.where(id: customer1.id)
      exporter = test_exporter_class.new(business: business, records: records)

      csv = exporter.export
      lines = CSV.parse(csv)

      # Header + 1 data row
      expect(lines.length).to eq(2)
    end
  end

  describe '#template' do
    it 'includes headers' do
      exporter = test_exporter_class.new(business: business)
      csv = exporter.template
      lines = CSV.parse(csv)

      expect(lines.first).to eq(%w[id name value])
    end
  end

  describe '#filename' do
    it 'includes export name, business name, and date' do
      exporter = test_exporter_class.new(business: business)
      filename = exporter.filename

      expect(filename).to include('test-export')
      expect(filename).to include(business.name.parameterize)
      expect(filename).to include(Date.current.to_s)
      expect(filename).to end_with('.csv')
    end
  end

  describe 'helper methods' do
    let(:exporter) { test_exporter_class.new(business: business) }

    describe '#format_datetime' do
      it 'formats datetime as ISO8601' do
        time = Time.zone.parse('2025-01-15 10:30:00')
        expect(exporter.send(:format_datetime, time)).to eq(time.iso8601)
      end

      it 'returns nil for nil input' do
        expect(exporter.send(:format_datetime, nil)).to be_nil
      end
    end

    describe '#format_date' do
      it 'formats date as YYYY-MM-DD' do
        date = Date.new(2025, 1, 15)
        expect(exporter.send(:format_date, date)).to eq('2025-01-15')
      end

      it 'returns nil for nil input' do
        expect(exporter.send(:format_date, nil)).to be_nil
      end
    end

    describe '#format_boolean' do
      it 'returns true string for true' do
        expect(exporter.send(:format_boolean, true)).to eq('true')
      end

      it 'returns false string for false' do
        expect(exporter.send(:format_boolean, false)).to eq('false')
      end
    end

    describe '#format_currency' do
      it 'formats to 2 decimal places' do
        expect(exporter.send(:format_currency, BigDecimal('19.999'))).to eq(20.0)
        expect(exporter.send(:format_currency, BigDecimal('5'))).to eq(5.0)
      end

      it 'returns nil for nil input' do
        expect(exporter.send(:format_currency, nil)).to be_nil
      end
    end
  end
end

