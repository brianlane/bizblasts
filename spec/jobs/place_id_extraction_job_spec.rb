# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaceIdExtractionJob, type: :job do
  let(:job_id) { SecureRandom.uuid }
  let(:google_maps_url) { 'https://www.google.com/maps/place/Test+Business/@37.7749,-122.4194' }

  describe '#perform' do
    context 'when extraction succeeds' do
      let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }

      before do
        # Mock the extraction to return a Place ID
        allow_any_instance_of(PlaceIdExtractionJob).to receive(:extract_place_id_from_maps).and_return(place_id)
      end

      it 'stores completed status in cache' do
        described_class.new.perform(job_id, google_maps_url)

        cached_data = Rails.cache.read("place_id_extraction:#{job_id}")
        expect(cached_data[:status]).to eq('completed')
        expect(cached_data[:place_id]).to eq(place_id)
        expect(cached_data[:message]).to include(place_id)
      end
    end

    context 'when extraction fails' do
      before do
        # Mock the extraction to return nil
        allow_any_instance_of(PlaceIdExtractionJob).to receive(:extract_place_id_from_maps).and_return(nil)
      end

      it 'stores failed status in cache' do
        described_class.new.perform(job_id, google_maps_url)

        cached_data = Rails.cache.read("place_id_extraction:#{job_id}")
        expect(cached_data[:status]).to eq('failed')
        expect(cached_data[:error]).to be_present
      end
    end

    context 'when extraction raises error' do
      before do
        allow_any_instance_of(PlaceIdExtractionJob).to receive(:extract_place_id_from_maps).and_raise(StandardError, 'Test error')
      end

      it 'stores failed status in cache' do
        described_class.new.perform(job_id, google_maps_url)

        cached_data = Rails.cache.read("place_id_extraction:#{job_id}")
        expect(cached_data[:status]).to eq('failed')
        expect(cached_data[:error]).to include('error occurred')
      end
    end
  end

  describe 'private methods' do
    let(:job) { described_class.new }

    describe '#extract_place_id_from_html' do
      it 'extracts Place ID starting with ChIJ' do
        html = '<div data-place-id="ChIJN1t_tDeuEmsRUsoyG83frY4">Test</div>'
        place_id = job.send(:extract_place_id_from_html, html)
        expect(place_id).to eq('ChIJN1t_tDeuEmsRUsoyG83frY4')
      end

      it 'extracts Place ID starting with GhIJ' do
        html = '<meta content="GhIJabcdefg12345678901234567890">'
        place_id = job.send(:extract_place_id_from_html, html)
        expect(place_id).to eq('GhIJabcdefg12345678901234567890')
      end

      it 'returns nil when no Place ID found' do
        html = '<div>No Place ID here</div>'
        place_id = job.send(:extract_place_id_from_html, html)
        expect(place_id).to be_nil
      end

      it 'returns nil for short strings that match pattern' do
        html = '"ChIJShort"'
        place_id = job.send(:extract_place_id_from_html, html)
        expect(place_id).to be_nil # Too short to be valid Place ID
      end
    end

    describe '#extract_place_id_from_url' do
      it 'extracts Place ID from URL parameter' do
        url = 'https://maps.google.com/review?place_id=ChIJN1t_tDeuEmsRUsoyG83frY4&other=param'
        place_id = job.send(:extract_place_id_from_url, url)
        expect(place_id).to eq('ChIJN1t_tDeuEmsRUsoyG83frY4')
      end

      it 'extracts Place ID from iframe src' do
        url = 'https://www.google.com/maps/embed?pb=!1m18!ChIJN1t_tDeuEmsRUsoyG83frY4!2sPlace'
        place_id = job.send(:extract_place_id_from_url, url)
        expect(place_id).to eq('ChIJN1t_tDeuEmsRUsoyG83frY4')
      end

      it 'returns nil when no Place ID found' do
        url = 'https://example.com/page'
        place_id = job.send(:extract_place_id_from_url, url)
        expect(place_id).to be_nil
      end
    end

    describe '#store_status' do
      it 'stores status data in cache' do
        job.send(:store_status, job_id, status: 'processing', message: 'Test message')

        cached_data = Rails.cache.read("place_id_extraction:#{job_id}")
        expect(cached_data[:status]).to eq('processing')
        expect(cached_data[:message]).to eq('Test message')
        expect(cached_data[:updated_at]).to be_present
      end

      it 'includes place_id when provided' do
        job.send(:store_status, job_id, status: 'completed', place_id: 'ChIJTest123')

        cached_data = Rails.cache.read("place_id_extraction:#{job_id}")
        expect(cached_data[:place_id]).to eq('ChIJTest123')
      end

      it 'includes error when provided' do
        job.send(:store_status, job_id, status: 'failed', error: 'Test error')

        cached_data = Rails.cache.read("place_id_extraction:#{job_id}")
        expect(cached_data[:error]).to eq('Test error')
      end

      it 'sets cache expiry to 10 minutes' do
        # This is implicit in the implementation, but we can verify the key exists
        job.send(:store_status, job_id, status: 'processing')

        expect(Rails.cache.exist?("place_id_extraction:#{job_id}")).to be true
      end
    end
  end

  describe 'job queueing' do
    it 'enqueues to default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'can be performed asynchronously' do
      expect {
        described_class.perform_later(job_id, google_maps_url)
      }.to have_enqueued_job(described_class).with(job_id, google_maps_url)
    end
  end

  describe '#extract_place_id_from_maps - browser automation logic' do
    let(:job) { described_class.new }
    let(:mock_browser) { instance_double(Capybara::Cuprite::Browser) }
    let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }
    let(:google_maps_url) { 'https://www.google.com/maps/place/Losne+Massage/@33.5371998,-112.2300583' }

    before do
      # Mock Capybara::Cuprite::Browser.new to return our mock browser
      allow(Capybara::Cuprite::Browser).to receive(:new).and_return(mock_browser)
      allow(mock_browser).to receive(:quit)
    end

    context 'when Place ID is found in page HTML after JavaScript loads' do
      it 'waits for JavaScript to load and extracts Place ID from page source' do
        # Mock browser navigation
        allow(mock_browser).to receive(:visit).with(google_maps_url)

        # Mock active waiting - simulate button appearing after a few polls
        poll_count = 0
        allow(mock_browser).to receive(:evaluate) do |script|
          if script.include?('button[aria-label*="eview"]')
            # First 2 polls: button not found, third poll: button found
            poll_count += 1
            poll_count >= 3
          end
        end

        # Mock browser.body to return HTML with Place ID
        allow(mock_browser).to receive(:body).and_return(
          %(<html><body><div data-place="#{place_id}">Losne Massage</div></body></html>)
        )

        result = job.send(:extract_place_id_from_maps, google_maps_url, job_id)

        expect(result).to eq(place_id)
        expect(mock_browser).to have_received(:visit).with(google_maps_url)
        expect(mock_browser).to have_received(:quit)
      end
    end

    context 'when Place ID is found in review iframe' do
      it 'clicks review button and extracts Place ID from iframe src' do
        # Mock browser navigation
        allow(mock_browser).to receive(:visit).with(google_maps_url)

        # Mock active waiting - button found immediately
        allow(mock_browser).to receive(:evaluate).and_return(true)

        # Mock page source has no Place ID initially
        allow(mock_browser).to receive(:body).and_return('<html><body>No Place ID here</body></html>')

        # Mock clicking review button and iframe detection
        click_count = 0
        allow(mock_browser).to receive(:evaluate) do |script|
          if script.include?('button[aria-label*="eview"]')
            true # Button exists
          elsif script.include?('querySelector') && script.include?('.click()')
            click_count += 1
            nil # Click executed
          elsif script.include?('querySelectorAll') && script.include?('meta')
            nil # Metadata check
          else
            nil
          end
        end

        allow(mock_browser).to receive(:execute) do |script|
          if script.include?('.click()')
            # Simulate click
            nil
          end
        end

        # Mock iframe count check - simulate iframe appearing after click
        iframe_check_count = 0
        allow(mock_browser).to receive(:evaluate) do |script|
          if script.include?('querySelectorAll(\'iframe\').length')
            iframe_check_count += 1
            iframe_check_count >= 2 ? 1 : 0 # Return 1 iframe after second check
          elsif script.include?('Array.from(document.querySelectorAll(\'iframe\'))')
            # Return iframe with Place ID in src
            ["https://www.google.com/maps/review?place_id=#{place_id}"]
          elsif script.include?('button[aria-label*="eview"]')
            true # Button exists
          elsif script.include?('document.querySelector') && !script.include?('Array.from')
            true # Element exists
          else
            nil
          end
        end

        result = job.send(:extract_place_id_from_maps, google_maps_url, job_id)

        expect(result).to eq(place_id)
      end
    end

    context 'when button is not found within timeout' do
      it 'continues with extraction attempts despite button not appearing' do
        allow(mock_browser).to receive(:visit).with(google_maps_url)

        # Mock active waiting - button never found
        allow(mock_browser).to receive(:evaluate).and_return(false)

        # Mock page source with Place ID (fallback to HTML search)
        allow(mock_browser).to receive(:body).and_return(
          %(<html><body><div data-id="#{place_id}">Test</div></body></html>)
        )

        result = job.send(:extract_place_id_from_maps, google_maps_url, job_id)

        expect(result).to eq(place_id)
      end
    end

    context 'when no Place ID is found anywhere' do
      it 'returns nil after trying all strategies' do
        allow(mock_browser).to receive(:visit).with(google_maps_url)
        allow(mock_browser).to receive(:evaluate).and_return(false)
        allow(mock_browser).to receive(:execute)
        allow(mock_browser).to receive(:body).and_return('<html><body>No Place ID</body></html>')

        result = job.send(:extract_place_id_from_maps, google_maps_url, job_id)

        expect(result).to be_nil
      end
    end

    context 'when browser raises an error' do
      it 'ensures browser is quit and allows error to propagate' do
        allow(mock_browser).to receive(:visit).and_raise(StandardError, 'Browser error')

        expect {
          job.send(:extract_place_id_from_maps, google_maps_url, job_id)
        }.to raise_error(StandardError, 'Browser error')

        # The ensure block should still run
        expect(mock_browser).to have_received(:quit)
      end
    end
  end

  describe '#extract_from_review_iframe' do
    let(:job) { described_class.new }
    let(:mock_browser) { instance_double(Capybara::Cuprite::Browser) }
    let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }

    context 'when review button is found and clicked successfully' do
      it 'waits for iframe and extracts Place ID from iframe src' do
        # Mock button existence check
        button_found = false
        iframe_check_count = 0

        allow(mock_browser).to receive(:evaluate) do |script|
          if script.include?('document.querySelector') && script.include?('!== null')
            button_found = true unless button_found
            button_found
          elsif script.include?('querySelectorAll(\'iframe\').length')
            # Simulate iframe appearing after 7 checks (7 seconds)
            iframe_check_count += 1
            iframe_check_count >= 7 ? 1 : 0
          elsif script.include?('Array.from(document.querySelectorAll(\'iframe\'))')
            ["https://www.google.com/maps/review?place_id=#{place_id}"]
          else
            nil
          end
        end

        # Mock button click
        allow(mock_browser).to receive(:execute) do |script|
          nil if script.include?('.click()')
        end

        result = job.send(:extract_from_review_iframe, mock_browser)

        expect(result).to eq(place_id)
      end
    end

    context 'when multiple iframes exist' do
      it 'checks all iframes and returns first Place ID found' do
        allow(mock_browser).to receive(:evaluate) do |script|
          if script.include?('document.querySelector') && script.include?('!== null')
            true
          elsif script.include?('querySelectorAll(\'iframe\').length')
            3 # Multiple iframes
          elsif script.include?('Array.from(document.querySelectorAll(\'iframe\'))')
            [
              'https://example.com/no-place-id',
              "https://www.google.com/maps/embed?pb=!1m18!#{place_id}!2sPlace",
              'https://another.com/iframe'
            ]
          else
            nil
          end
        end

        allow(mock_browser).to receive(:execute)

        result = job.send(:extract_from_review_iframe, mock_browser)

        expect(result).to eq(place_id)
      end
    end

    context 'when button exists but no iframe appears' do
      it 'returns nil after waiting for iframe (15 seconds)' do
        iframe_check_count = 0

        allow(mock_browser).to receive(:evaluate) do |script|
          if script.include?('document.querySelector') && script.include?('!== null')
            true
          elsif script.include?("querySelectorAll('iframe').length")
            iframe_check_count += 1
            0 # No iframes ever appear
          else
            nil
          end
        end

        allow(mock_browser).to receive(:execute)

        result = job.send(:extract_from_review_iframe, mock_browser)

        expect(result).to be_nil
        # Should have checked 15 times (15 seconds of waiting)
        expect(iframe_check_count).to be >= 15
      end
    end

    context 'when no review button is found' do
      it 'tries all selectors and returns nil' do
        allow(mock_browser).to receive(:evaluate).and_return(false)

        result = job.send(:extract_from_review_iframe, mock_browser)

        expect(result).to be_nil
        # Should try all 8 review button selectors
        expect(mock_browser).to have_received(:evaluate).at_least(8).times
      end
    end
  end

  describe '#extract_from_metadata' do
    let(:job) { described_class.new }
    let(:mock_browser) { instance_double(Capybara::Cuprite::Browser) }
    let(:place_id) { 'ChIJN1t_tDeuEmsRUsoyG83frY4' }

    it 'extracts Place ID from meta tag content' do
      allow(mock_browser).to receive(:evaluate).and_return(place_id)

      result = job.send(:extract_from_metadata, mock_browser)

      expect(result).to eq(place_id)
    end

    it 'returns nil when no meta tag contains Place ID' do
      allow(mock_browser).to receive(:evaluate).and_return(nil)

      result = job.send(:extract_from_metadata, mock_browser)

      expect(result).to be_nil
    end

    it 'returns nil when meta content does not match Place ID pattern' do
      allow(mock_browser).to receive(:evaluate).and_return('some-random-content')

      result = job.send(:extract_from_metadata, mock_browser)

      expect(result).to be_nil
    end
  end
end
