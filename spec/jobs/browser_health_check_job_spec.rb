# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BrowserHealthCheckJob, type: :job do
  describe '#perform' do
    let(:browser_path) { '/usr/bin/google-chrome' }

    before do
      # Clear cache before each test
      Rails.cache.clear
    end

    context 'when browser is found and functional' do
      before do
        allow(PlaceIdExtraction::BrowserPathResolver).to receive(:resolve).and_return(browser_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(browser_path).and_return(true)
        allow(File).to receive(:executable?).with(browser_path).and_return(true)
        # Mock check_browser_version to return a version string
        allow_any_instance_of(described_class).to receive(:check_browser_version).and_return('Google Chrome 132.0.6834.83')
      end

      it 'marks browser as healthy' do
        described_class.new.perform

        status = Rails.cache.read('browser_health_check:status')
        expect(status[:healthy]).to be true
        expect(status[:browser_path]).to eq(browser_path)
        expect(status[:version]).to include('Chrome')
      end

      it 'logs successful health check' do
        # Allow all logger calls but verify specific messages are logged
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with(/Browser found at/).and_call_original.at_least(:once)
        expect(Rails.logger).to receive(:info).with(/Browser is executable/).and_call_original.at_least(:once)
        expect(Rails.logger).to receive(:info).with(/Browser version:/).and_call_original.at_least(:once)

        described_class.new.perform
      end
    end

    context 'when browser is not found' do
      before do
        allow(PlaceIdExtraction::BrowserPathResolver).to receive(:resolve).and_return(nil)
      end

      it 'marks browser as unhealthy' do
        described_class.new.perform

        status = Rails.cache.read('browser_health_check:status')
        expect(status[:healthy]).to be false
        expect(status[:message]).to include('No browser executable found')
      end

      it 'logs warning' do
        expect(Rails.logger).to receive(:warn).with(/No browser executable found/).at_least(:once)

        described_class.new.perform
      end
    end

    context 'when browser is found but not executable' do
      before do
        allow(PlaceIdExtraction::BrowserPathResolver).to receive(:resolve).and_return(browser_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(browser_path).and_return(true)
        allow(File).to receive(:executable?).with(browser_path).and_return(false)
      end

      it 'marks browser as unhealthy' do
        described_class.new.perform

        status = Rails.cache.read('browser_health_check:status')
        expect(status[:healthy]).to be false
        expect(status[:message]).to include('not executable')
      end
    end

    context 'when browser version check fails' do
      before do
        allow(PlaceIdExtraction::BrowserPathResolver).to receive(:resolve).and_return(browser_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(browser_path).and_return(true)
        allow(File).to receive(:executable?).with(browser_path).and_return(true)
        # Mock check_browser_version to return nil (indicating failure)
        allow_any_instance_of(described_class).to receive(:check_browser_version).and_return(nil)
      end

      it 'marks browser as unhealthy' do
        described_class.new.perform

        status = Rails.cache.read('browser_health_check:status')
        expect(status[:healthy]).to be false
        expect(status[:message]).to include('version check failed')
      end
    end

    context 'when health check raises an error' do
      before do
        allow(PlaceIdExtraction::BrowserPathResolver).to receive(:resolve).and_raise(StandardError, 'Test error')
      end

      it 'stores unhealthy status' do
        expect { described_class.new.perform }.to raise_error(StandardError)

        status = Rails.cache.read('browser_health_check:status')
        expect(status[:healthy]).to be false
        expect(status[:message]).to include('Test error')
      end

      it 'logs error' do
        # Allow all logger calls but verify the error is logged
        allow(Rails.logger).to receive(:error).and_call_original
        expect(Rails.logger).to receive(:error).with(/Health check failed/).and_call_original.at_least(:once)

        expect { described_class.new.perform }.to raise_error(StandardError)
      end
    end

    describe 'extraction metrics checking' do
      before do
        allow(PlaceIdExtraction::BrowserPathResolver).to receive(:resolve).and_return(browser_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(browser_path).and_return(true)
        allow(File).to receive(:executable?).with(browser_path).and_return(true)
        # Mock check_browser_version
        allow_any_instance_of(described_class).to receive(:check_browser_version).and_return('Google Chrome 132.0.6834.83')
      end

      it 'reports recent metrics when available' do
        # Set up some metrics
        Rails.cache.write("place_id_extraction:metrics:success:#{Date.current}", 10, expires_in: 7.days)
        Rails.cache.write("place_id_extraction:metrics:error:#{Date.current}", 2, expires_in: 7.days)

        # Allow all logger calls but verify specific metrics messages are logged
        allow(Rails.logger).to receive(:info).and_call_original
        expect(Rails.logger).to receive(:info).with(/Recent metrics/).and_call_original.at_least(:once)
        expect(Rails.logger).to receive(:info).with(/Success: 10/).and_call_original.at_least(:once)

        described_class.new.perform
      end

      it 'warns about low success rate' do
        # Set up metrics with low success rate
        Rails.cache.write("place_id_extraction:metrics:success:#{Date.current}", 2, expires_in: 7.days)
        Rails.cache.write("place_id_extraction:metrics:error:#{Date.current}", 8, expires_in: 7.days)

        expect(Rails.logger).to receive(:warn).with(/Low success rate detected/).at_least(:once)

        described_class.new.perform
      end
    end
  end
end
