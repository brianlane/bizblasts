# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calendar::CaldavFactory do
  describe '.url_host_matches?' do
    context 'with valid matching URLs' do
      it 'matches exact host' do
        expect(described_class.url_host_matches?('https://caldav.icloud.com', 'caldav.icloud.com')).to be true
      end

      it 'matches exact host with path' do
        expect(described_class.url_host_matches?('https://caldav.icloud.com/calendars/home', 'caldav.icloud.com')).to be true
      end

      it 'is case-insensitive' do
        expect(described_class.url_host_matches?('https://CALDAV.ICLOUD.COM', 'caldav.icloud.com')).to be true
      end

      it 'matches exact host with port' do
        expect(described_class.url_host_matches?('https://caldav.icloud.com:8443', 'caldav.icloud.com')).to be true
      end
    end

    context 'with URL substring injection attacks (CWE-20)' do
      it 'rejects URL with trusted string in path' do
        # Primary vulnerability: attacker puts trusted domain in path
        expect(described_class.url_host_matches?('https://evil.com/caldav.icloud.com', 'caldav.icloud.com')).to be false
      end

      it 'rejects URL with trusted string in query parameter' do
        expect(described_class.url_host_matches?('https://attacker.net?redirect=caldav.icloud.com', 'caldav.icloud.com')).to be false
      end

      it 'rejects URL with trusted string in subdomain' do
        expect(described_class.url_host_matches?('https://caldav.icloud.com.evil.com', 'caldav.icloud.com')).to be false
      end

      it 'rejects URL with trusted string in username' do
        expect(described_class.url_host_matches?('https://caldav.icloud.com@evil.com', 'caldav.icloud.com')).to be false
      end

      it 'rejects URL with partial host match' do
        expect(described_class.url_host_matches?('https://fake-caldav.icloud.com', 'caldav.icloud.com')).to be false
      end
    end

    context 'with invalid inputs' do
      it 'returns false for blank URL' do
        expect(described_class.url_host_matches?('', 'caldav.icloud.com')).to be false
        expect(described_class.url_host_matches?(nil, 'caldav.icloud.com')).to be false
      end

      it 'returns false for malformed URL' do
        expect(described_class.url_host_matches?('not a url', 'caldav.icloud.com')).to be false
        expect(described_class.url_host_matches?('ht!tp://invalid', 'caldav.icloud.com')).to be false
      end

      it 'returns false when URL has no host' do
        expect(described_class.url_host_matches?('mailto:user@example.com', 'example.com')).to be false
      end
    end
  end

  describe '.url_path_contains?' do
    context 'with valid path matches' do
      it 'finds string in path' do
        expect(described_class.url_path_contains?('https://cloud.example.com/remote.php/dav', 'remote.php/dav')).to be true
      end

      it 'is case-insensitive' do
        expect(described_class.url_path_contains?('https://cloud.example.com/REMOTE.PHP/DAV', 'remote.php/dav')).to be true
      end

      it 'finds partial path match' do
        expect(described_class.url_path_contains?('https://cloud.example.com/remote.php/dav/calendars', 'remote.php/dav')).to be true
      end
    end

    context 'security: does not match host' do
      it 'does not match string in host' do
        # Security test: ensure we're checking path, not entire URL
        expect(described_class.url_path_contains?('https://remote.php.example.com/calendars', 'remote.php/dav')).to be false
      end

      it 'does not match string in query parameter' do
        expect(described_class.url_path_contains?('https://example.com?path=remote.php/dav', 'remote.php/dav')).to be false
      end
    end

    context 'with invalid inputs' do
      it 'returns false for blank URL' do
        expect(described_class.url_path_contains?('', 'remote.php/dav')).to be false
        expect(described_class.url_path_contains?(nil, 'remote.php/dav')).to be false
      end

      it 'returns false for malformed URL' do
        expect(described_class.url_path_contains?('not a url', 'remote.php/dav')).to be false
      end
    end
  end

  describe '.url_host_contains?' do
    context 'with valid host matches' do
      it 'finds substring in host' do
        expect(described_class.url_host_contains?('https://my-nextcloud.example.com', 'nextcloud')).to be true
      end

      it 'is case-insensitive' do
        expect(described_class.url_host_contains?('https://MY-NEXTCLOUD.COM', 'nextcloud')).to be true
      end

      it 'finds substring at start of host' do
        expect(described_class.url_host_contains?('https://nextcloud.example.com', 'nextcloud')).to be true
      end

      it 'finds substring at end of host' do
        expect(described_class.url_host_contains?('https://cloud-nextcloud.com', 'nextcloud')).to be true
      end
    end

    context 'security: only matches host, not path' do
      it 'does not match string in path' do
        # Security test: ensure we're checking host, not entire URL
        expect(described_class.url_host_contains?('https://example.com/nextcloud', 'nextcloud')).to be false
      end

      it 'does not match string in query parameter' do
        expect(described_class.url_host_contains?('https://example.com?server=nextcloud', 'nextcloud')).to be false
      end
    end

    context 'with invalid inputs' do
      it 'returns false for blank URL' do
        expect(described_class.url_host_contains?('', 'nextcloud')).to be false
        expect(described_class.url_host_contains?(nil, 'nextcloud')).to be false
      end

      it 'returns false for malformed URL' do
        expect(described_class.url_host_contains?('not a url', 'nextcloud')).to be false
      end
    end
  end

  describe '.detect_provider' do
    let(:business) { create(:business) }
    let(:staff_member) { create(:staff_member, business: business) }

    context 'with iCloud detection' do
      it 'detects iCloud from @icloud.com email' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@icloud.com',
          caldav_password: 'password',
          caldav_url: 'https://caldav.icloud.com',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:icloud)
      end

      it 'detects iCloud from @me.com email' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@me.com',
          caldav_password: 'password',
          caldav_url: 'https://caldav.icloud.com',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:icloud)
      end

      it 'detects iCloud from @mac.com email' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@mac.com',
          caldav_password: 'password',
          caldav_url: 'https://caldav.icloud.com',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:icloud)
      end

      it 'detects iCloud from exact URL host match' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@example.com',
          caldav_password: 'password',
          caldav_url: 'https://caldav.icloud.com/calendars/home',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:icloud)
      end

      it 'does NOT detect iCloud from malicious URL with caldav.icloud.com in path' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@example.com',
          caldav_password: 'password',
          caldav_url: 'https://evil.com/caldav.icloud.com',
          active: false
        )
        # Should fall back to generic, not icloud
        expect(described_class.detect_provider(connection)).to eq(:generic)
      end
    end

    context 'with Nextcloud detection' do
      it 'detects Nextcloud from host substring' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user',
          caldav_password: 'password',
          caldav_url: 'https://my-nextcloud.example.com',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:nextcloud)
      end

      it 'detects ownCloud from host substring' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user',
          caldav_password: 'password',
          caldav_url: 'https://owncloud.example.com',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:nextcloud)
      end

      it 'detects Nextcloud from remote.php/dav path' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user',
          caldav_password: 'password',
          caldav_url: 'https://cloud.example.com/remote.php/dav/calendars',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:nextcloud)
      end

      it 'does NOT detect Nextcloud from nextcloud in path only' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user',
          caldav_password: 'password',
          caldav_url: 'https://evil.com/nextcloud',
          active: false
        )
        # Should fall back to generic
        expect(described_class.detect_provider(connection)).to eq(:generic)
      end
    end

    context 'with explicit provider setting' do
      it 'respects explicit caldav_provider setting' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user',
          caldav_password: 'password',
          caldav_url: 'https://example.com',
          caldav_provider: 'icloud',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:icloud)
      end
    end

    context 'with generic fallback' do
      it 'falls back to generic for unknown providers' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user',
          caldav_password: 'password',
          caldav_url: 'https://caldav.fastmail.com',
          active: false
        )
        expect(described_class.detect_provider(connection)).to eq(:generic)
      end
    end
  end
end
