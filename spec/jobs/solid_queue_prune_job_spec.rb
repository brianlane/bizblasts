# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SolidQueuePruneJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Time.zone.parse('2025-01-01 00:00:00 UTC')) { example.run }
  end

  describe '#perform' do
    it 'runs the pruner with the default retention window' do
      allow(SolidQueue::Pruner).to receive(:run)

      described_class.perform_now

      expect(SolidQueue::Pruner).to have_received(:run) do |args|
        expect(args[:older_than]).to be_within(1.second).of(14.days.ago)
      end
    end

    it 'accepts a custom retention window via arguments' do
      allow(SolidQueue::Pruner).to receive(:run)

      described_class.perform_now(retention_days: 7)

      expect(SolidQueue::Pruner).to have_received(:run) do |args|
        expect(args[:older_than]).to be_within(1.second).of(7.days.ago)
      end
    end

    it 'falls back to defaults when the env var is invalid' do
      allow(SolidQueue::Pruner).to receive(:run)
      original = ENV['SOLID_QUEUE_RETENTION_DAYS']

      begin
        ENV['SOLID_QUEUE_RETENTION_DAYS'] = 'not-a-number'
        described_class.perform_now
      ensure
        ENV['SOLID_QUEUE_RETENTION_DAYS'] = original
      end

      expect(SolidQueue::Pruner).to have_received(:run) do |args|
        expect(args[:older_than]).to be_within(1.second).of(14.days.ago)
      end
    end
  end
end

