# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::RefreshMaterializedViewsJob, type: :job do
  describe '#perform' do
    context 'when views exist' do
      before do
        # Mock the view existence
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return(nil)
      end

      it 'refreshes all materialized views' do
        expect(ActiveRecord::Base.connection).to receive(:execute).exactly(3).times
        described_class.new.perform(concurrently: true)
      end

      it 'returns results hash with success status' do
        results = described_class.new.perform(concurrently: true)

        expect(results).to be_a(Hash)
        expect(results.keys).to match_array(described_class::VIEWS)
        results.each_value do |result|
          expect(result[:success]).to be true
          expect(result[:duration]).to be_a(Float)
        end
      end

      it 'logs refresh timing' do
        expect(Rails.logger).to receive(:info).at_least(:once)
        described_class.new.perform
      end
    end

    context 'when concurrent refresh fails' do
      it 'falls back to non-concurrent refresh' do
        # Allow first call to raise, subsequent calls to succeed
        call_count = 0
        allow(ActiveRecord::Base.connection).to receive(:execute) do |sql|
          call_count += 1
          if call_count == 1 && sql.include?('CONCURRENTLY')
            raise ActiveRecord::StatementInvalid.new("cannot refresh materialized view concurrently")
          end
          nil
        end

        expect(Rails.logger).to receive(:warn).with(/Falling back to non-concurrent refresh/).at_least(:once)
        described_class.new.perform(concurrently: true)
      end
    end

    context 'when refresh fails' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute)
          .and_raise(StandardError.new("Database error"))
      end

      it 'logs error and continues' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        results = described_class.new.perform

        results.each_value do |result|
          expect(result[:success]).to be false
          expect(result[:error]).to eq("Database error")
        end
      end
    end

    it 'validates view names for security' do
      job = described_class.new
      expect { job.send(:refresh_view, 'malicious_view', concurrently: false) }
        .to raise_error(ArgumentError, /Invalid view name/)
    end
  end

  describe 'VIEWS constant' do
    it 'includes expected views' do
      expect(described_class::VIEWS).to include('daily_analytics_summaries')
      expect(described_class::VIEWS).to include('traffic_source_summaries')
      expect(described_class::VIEWS).to include('top_pages_summaries')
    end
  end
end
