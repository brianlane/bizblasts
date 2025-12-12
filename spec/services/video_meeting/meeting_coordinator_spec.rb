# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMeeting::MeetingCoordinator do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:service) { create(:service, :with_zoom, business: business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:booking) do
    create(:booking,
           business: business,
           staff_member: staff_member,
           service: service,
           tenant_customer: customer,
           status: :confirmed,
           start_time: 1.day.from_now,
           end_time: 1.day.from_now + 1.hour)
  end
  let(:connection) do
    create(:video_meeting_connection,
           business: business,
           staff_member: staff_member,
           provider: :zoom,
           access_token: 'test_token',
           refresh_token: 'test_refresh',
           token_expires_at: 1.hour.from_now,
           active: true)
  end

  before do
    ActsAsTenant.current_tenant = business
  end

  subject(:coordinator) { described_class.new(booking) }

  describe '#initialize' do
    it 'sets booking' do
      expect(coordinator.booking).to eq(booking)
    end

    it 'initializes empty errors' do
      expect(coordinator.errors).to be_empty
    end
  end

  describe '.create_meeting_for_booking' do
    it 'creates coordinator and calls create_meeting' do
      coordinator_double = instance_double(described_class)
      allow(described_class).to receive(:new).with(booking).and_return(coordinator_double)
      expect(coordinator_double).to receive(:create_meeting)

      described_class.create_meeting_for_booking(booking)
    end
  end

  describe '#create_meeting' do
    context 'when service does not have video meetings enabled' do
      before do
        service.update!(video_enabled: false)
      end

      it 'returns false' do
        expect(coordinator.create_meeting).to be false
      end

      it 'adds error' do
        coordinator.create_meeting
        expect(coordinator.errors[:service_not_enabled]).to be_present
      end
    end

    context 'when booking has no staff member' do
      before do
        booking.update_column(:staff_member_id, nil)
      end

      it 'returns false' do
        expect(coordinator.create_meeting).to be false
      end

      it 'adds error' do
        coordinator.create_meeting
        expect(coordinator.errors[:no_staff_member]).to be_present
      end
    end

    context 'when staff member has no video connection' do
      it 'returns false' do
        expect(coordinator.create_meeting).to be false
      end

      it 'adds error' do
        coordinator.create_meeting
        expect(coordinator.errors[:no_connection]).to be_present
      end

      it 'marks booking as failed' do
        coordinator.create_meeting
        booking.reload
        expect(booking.video_meeting_video_failed?).to be true
      end
    end

    context 'when staff member has a valid video connection' do
      before do
        connection # create the connection
      end

      let(:meeting_data) do
        {
          meeting_id: '123456789',
          join_url: 'https://zoom.us/j/123456789',
          host_url: 'https://zoom.us/s/123456789',
          password: 'test_meeting_pwd',
          provider: 'zoom'
        }
      end

      it 'calls zoom service to create meeting' do
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_return(meeting_data)
        allow(zoom_service).to receive(:errors).and_return([])

        expect(coordinator.create_meeting).to be true
      end

      it 'updates booking with meeting data' do
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_return(meeting_data)
        allow(zoom_service).to receive(:errors).and_return([])

        coordinator.create_meeting
        booking.reload

        expect(booking.video_meeting_id).to eq('123456789')
        expect(booking.video_meeting_url).to eq('https://zoom.us/j/123456789')
        expect(booking.video_meeting_host_url).to eq('https://zoom.us/s/123456789')
        expect(booking.video_meeting_password).to eq('test_meeting_pwd')
        expect(booking.video_video_zoom?).to be true
        expect(booking.video_meeting_video_created?).to be true
      end

      context 'when service returns nil' do
        it 'returns false and marks booking as failed' do
          zoom_service = instance_double(VideoMeeting::ZoomService)
          allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
          allow(zoom_service).to receive(:create_meeting).and_return(nil)
          allow(zoom_service).to receive(:errors).and_return(ActiveModel::Errors.new(zoom_service))

          expect(coordinator.create_meeting).to be false
          booking.reload
          expect(booking.video_meeting_video_failed?).to be true
        end
      end

      context 'when service returns invalid data' do
        it 'returns false when meeting_id is missing' do
          zoom_service = instance_double(VideoMeeting::ZoomService)
          allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
          allow(zoom_service).to receive(:create_meeting).and_return({ join_url: 'url' })
          allow(zoom_service).to receive(:errors).and_return(ActiveModel::Errors.new(zoom_service))

          expect(coordinator.create_meeting).to be false
          expect(coordinator.errors[:invalid_meeting_data]).to be_present
        end

        it 'returns false when join_url is missing' do
          zoom_service = instance_double(VideoMeeting::ZoomService)
          allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
          allow(zoom_service).to receive(:create_meeting).and_return({ meeting_id: '123' })
          allow(zoom_service).to receive(:errors).and_return(ActiveModel::Errors.new(zoom_service))

          expect(coordinator.create_meeting).to be false
          expect(coordinator.errors[:invalid_meeting_data]).to be_present
        end
      end
    end

    context 'with Google Meet provider' do
      before do
        service.update!(video_enabled: true, video_provider: :video_google_meet)
        connection.update!(provider: :google_meet)
      end

      let(:meeting_data) do
        {
          meeting_id: 'abc-defg-hij',
          join_url: 'https://meet.google.com/abc-defg-hij',
          host_url: nil,
          password: nil,
          provider: 'google_meet'
        }
      end

      it 'calls google meet service to create meeting' do
        google_service = instance_double(VideoMeeting::GoogleMeetService)
        allow(VideoMeeting::GoogleMeetService).to receive(:new).and_return(google_service)
        allow(google_service).to receive(:create_meeting).and_return(meeting_data)
        allow(google_service).to receive(:errors).and_return([])

        expect(coordinator.create_meeting).to be true
        booking.reload
        expect(booking.video_video_google_meet?).to be true
      end
    end

    context 'when an unexpected error occurs' do
      before do
        connection # create the connection
      end

      it 'catches the error and returns false' do
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_raise(StandardError.new('Unexpected error'))

        expect(coordinator.create_meeting).to be false
        expect(coordinator.errors[:unexpected_error]).to be_present
      end

      it 'marks booking as failed' do
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_raise(StandardError.new('Unexpected error'))

        coordinator.create_meeting
        booking.reload
        expect(booking.video_meeting_video_failed?).to be true
      end
    end
  end

  describe '#delete_meeting' do
    context 'when booking has no video meeting' do
      it 'returns true' do
        expect(coordinator.delete_meeting).to be true
      end
    end

    context 'when booking has a video meeting' do
      before do
        connection # create the connection
        booking.update!(
          video_meeting_id: '123456789',
          video_meeting_url: 'https://zoom.us/j/123456789',
          video_meeting_provider: :video_zoom,
          video_meeting_status: :video_created
        )
      end

      it 'calls service to delete meeting' do
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:delete_meeting).and_return(true)
        allow(zoom_service).to receive(:errors).and_return([])

        expect(coordinator.delete_meeting).to be true
      end

      it 'clears booking meeting data on success' do
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:delete_meeting).and_return(true)
        allow(zoom_service).to receive(:errors).and_return([])

        coordinator.delete_meeting
        booking.reload

        expect(booking.video_meeting_id).to be_nil
        expect(booking.video_meeting_url).to be_nil
        expect(booking.video_video_none?).to be true
        expect(booking.video_meeting_video_not_created?).to be true
      end

      context 'when connection is removed' do
        before do
          connection.destroy!
        end

        it 'returns true' do
          expect(coordinator.delete_meeting).to be true
        end
      end
    end
  end
end
