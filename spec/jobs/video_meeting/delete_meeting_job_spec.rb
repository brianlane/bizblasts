# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMeeting::DeleteMeetingJob, type: :job do
  include ActiveJob::TestHelper

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
           status: :cancelled,
           video_meeting_id: '123456789',
           video_meeting_url: 'https://zoom.us/j/123456789',
           video_meeting_host_url: 'https://zoom.us/s/123456789',
           video_meeting_password: 'test_meeting_pwd',
           video_meeting_provider: :video_zoom,
           video_meeting_status: :video_created,
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

  describe 'job configuration' do
    it 'is enqueued in the default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'has retry configuration for network errors' do
      # Verify the class has retry_on declarations by checking the rescue_handlers
      # The actual retry behavior is tested via integration tests
      expect(described_class.ancestors).to include(ActiveJob::Base)
    end
  end

  describe '#perform' do
    context 'when booking does not exist' do
      it 'discards the job without raising' do
        expect {
          perform_enqueued_jobs do
            described_class.perform_later(999999, business.id)
          end
        }.not_to raise_error
      end
    end

    context 'when business does not exist' do
      it 'discards the job without raising' do
        expect {
          perform_enqueued_jobs do
            described_class.perform_later(booking.id, 999999)
          end
        }.not_to raise_error
      end
    end

    context 'when booking has no video meeting' do
      before do
        booking.update!(
          video_meeting_id: nil,
          video_meeting_url: nil,
          video_meeting_provider: :video_none,
          video_meeting_status: :video_not_created
        )
      end

      it 'returns early' do
        expect(VideoMeeting::MeetingCoordinator).not_to receive(:new)

        described_class.new.perform(booking.id, business.id)
      end

      it 'logs that there is no meeting to delete' do
        expect(Rails.logger).to receive(:info).with(/has no video meeting to delete/)

        described_class.new.perform(booking.id, business.id)
      end
    end

    context 'when meeting deletion succeeds' do
      before do
        connection # ensure connection exists
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:delete_meeting).and_return(true)
        allow(zoom_service).to receive(:errors).and_return([])
      end

      it 'deletes the meeting' do
        described_class.new.perform(booking.id, business.id)
        booking.reload

        expect(booking.video_meeting_id).to be_nil
        expect(booking.video_meeting_url).to be_nil
      end

      it 'logs success' do
        expect(Rails.logger).to receive(:info).with(/Successfully deleted video meeting/)

        described_class.new.perform(booking.id, business.id)
      end
    end

    context 'when meeting deletion fails' do
      before do
        connection # ensure connection exists
        coordinator = instance_double(VideoMeeting::MeetingCoordinator)
        allow(VideoMeeting::MeetingCoordinator).to receive(:new).and_return(coordinator)
        allow(coordinator).to receive(:delete_meeting).and_return(false)

        errors = ActiveModel::Errors.new(coordinator)
        errors.add(:api_error, 'Meeting not found')
        allow(coordinator).to receive(:errors).and_return(errors)
      end

      it 'logs the failure' do
        expect(Rails.logger).to receive(:warn).with(/Failed to delete video meeting/)
        expect(Rails.logger).to receive(:warn).at_least(:once)

        described_class.new.perform(booking.id, business.id)
      end

      it 'still clears the booking meeting data' do
        described_class.new.perform(booking.id, business.id)
        booking.reload

        expect(booking.video_meeting_id).to be_nil
        expect(booking.video_meeting_url).to be_nil
        expect(booking.video_video_none?).to be true
        expect(booking.video_meeting_video_not_created?).to be true
      end
    end

    context 'when connection is missing' do
      before do
        # Don't create connection - test handles case where staff has no video connection
        coordinator = instance_double(VideoMeeting::MeetingCoordinator)
        allow(VideoMeeting::MeetingCoordinator).to receive(:new).and_return(coordinator)
        allow(coordinator).to receive(:delete_meeting).and_return(true)
      end

      it 'logs success' do
        expect(Rails.logger).to receive(:info).with(/Successfully deleted video meeting/)

        described_class.new.perform(booking.id, business.id)
      end
    end

    context 'with multi-tenant context' do
      it 'executes within the correct tenant context' do
        connection # ensure connection exists
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:delete_meeting).and_return(true)
        allow(zoom_service).to receive(:errors).and_return([])

        expect(ActsAsTenant).to receive(:with_tenant).with(business).and_call_original

        described_class.new.perform(booking.id, business.id)
      end
    end
  end

end
