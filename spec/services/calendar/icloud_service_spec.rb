# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calendar::IcloudService, type: :service do
  let(:calendar_connection) do
    instance_double(
      'CalendarConnection',
      caldav_username: 'user@icloud.com',
      caldav_password: 'password',
      caldav_url: '',
      caldav_provider: 'icloud',
      caldav_provider_display_name: 'iCloud Calendar',
      active?: true,
      business: nil,
      staff_member: nil
    )
  end

  subject(:service) { described_class.new(calendar_connection) }

  describe '#discover_principal_url' do
    it 'uses Depth 0 on the PROPFIND request to the root endpoint' do
      resp = double('Response', code: '207', message: 'OK', body: '<xml/>', success?: true)
      expect(service).to receive(:propfind_request).with(Calendar::IcloudService::CALDAV_BASE_URL, anything, '0').and_return(resp)
      allow(service).to receive(:discover_calendar_home_set).and_return(nil)
      service.send(:discover_principal_url)
    end
  end

  describe '#discover_calendar_home_set' do
    it 'uses Depth 0 when requesting calendar-home-set on the principal URL' do
      principal_url = 'https://caldav.icloud.com/123/principal/'
      resp = double('Response', code: '207', message: 'OK', body: '<xml/>', success?: true)
      expect(service).to receive(:propfind_request).with(principal_url, anything, '0').and_return(resp)
      # Stub href extraction so method returns without errors
      allow(service).to receive(:extract_href_from_response).and_return('/calendars/user/')
      service.send(:discover_calendar_home_set, principal_url)
    end
  end
end