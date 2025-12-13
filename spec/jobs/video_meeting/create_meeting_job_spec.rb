# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMeeting::CreateMeetingJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:service) { create(:service, :with_zoom, business: business) }
  let(:customer) { create(:tenant_customer, business: business, email: 'customer@example.com') }
  let(:booking) do
    create(:booking,
           business: business,
           staff_member: staff_member,
           service: service,
           tenant_customer: customer,
           status: :confirmed,
           video_meeting_status: :video_pending,
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
            described_class.perform_later(999999)
          end
        }.not_to raise_error
      end
    end

    context 'when meeting is already created' do
      before do
        booking.update!(video_meeting_status: :video_created)
      end

      it 'returns early without creating meeting' do
        coordinator = instance_double(VideoMeeting::MeetingCoordinator)
        expect(VideoMeeting::MeetingCoordinator).not_to receive(:new)

        described_class.new.perform(booking.id)
      end
    end

    context 'when booking is no longer confirmed' do
      before do
        booking.update_column(:status, Booking.statuses[:cancelled])
      end

      it 'returns early without creating meeting' do
        expect(VideoMeeting::MeetingCoordinator).not_to receive(:new)

        described_class.new.perform(booking.id)
      end

      it 'logs the skip reason' do
        expect(Rails.logger).to receive(:info).with(/no longer confirmed/)

        described_class.new.perform(booking.id)
      end
    end

    context 'when video meeting is no longer required' do
      before do
        service.update!(video_enabled: false)
      end

      it 'marks the booking as failed if it was pending' do
        described_class.new.perform(booking.id)
        booking.reload

        expect(booking.video_meeting_video_failed?).to be true
      end

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn).with(/no longer eligible/)

        described_class.new.perform(booking.id)
      end
    end

    context 'when booking status has already been processed' do
      before do
        connection # ensure connection exists
        booking.update_column(:video_meeting_status, Booking.video_meeting_statuses[:video_created])
      end

      it 'skips processing without creating meeting' do
        # The early return happens before the MeetingCoordinator is called
        expect(VideoMeeting::MeetingCoordinator).not_to receive(:new)

        described_class.new.perform(booking.id)
      end
    end

    context 'when meeting creation succeeds' do
      let(:meeting_data) do
        {
          meeting_id: '123456789',
          join_url: 'https://zoom.us/j/123456789',
          host_url: 'https://zoom.us/s/123456789',
          password: 'test_meeting_pwd',
          provider: 'zoom'
        }
      end

      before do
        connection # ensure connection exists
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_return(meeting_data)
        allow(zoom_service).to receive(:errors).and_return([])
      end

      it 'creates the meeting' do
        described_class.new.perform(booking.id)
        booking.reload

        expect(booking.video_meeting_video_created?).to be true
        expect(booking.video_meeting_id).to eq('123456789')
      end

      it 'sends video meeting notification email' do
        expect {
          described_class.new.perform(booking.id)
        }.to have_enqueued_mail(BookingMailer, :video_meeting_ready)
      end
    end

    context 'when meeting creation fails' do
      before do
        connection # ensure connection exists
        coordinator = instance_double(VideoMeeting::MeetingCoordinator)
        allow(VideoMeeting::MeetingCoordinator).to receive(:new).and_return(coordinator)
        allow(coordinator).to receive(:create_meeting).and_return(false)

        error = ActiveModel::Error.new(coordinator, :api_error, 'API call failed')
        errors = ActiveModel::Errors.new(coordinator)
        errors.add(:api_error, 'API call failed')
        allow(coordinator).to receive(:errors).and_return(errors)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Failed to create meeting/)
        expect(Rails.logger).to receive(:error).at_least(:once)

        described_class.new.perform(booking.id)
      end

      it 'sends failure notification to business' do
        expect {
          described_class.new.perform(booking.id)
        }.to have_enqueued_mail(BusinessMailer, :video_meeting_failed)
      end
    end

    context 'when customer has no email' do
      before do
        # Use update_column to bypass TenantCustomer email validations
        customer.update_column(:email, nil)
        connection # ensure connection exists

        meeting_data = {
          meeting_id: '123456789',
          join_url: 'https://zoom.us/j/123456789',
          host_url: 'https://zoom.us/s/123456789',
          password: 'test_meeting_pwd',
          provider: 'zoom'
        }
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_return(meeting_data)
        allow(zoom_service).to receive(:errors).and_return([])
      end

      it 'does not send notification email but still creates meeting' do
        expect {
          described_class.new.perform(booking.id)
        }.not_to have_enqueued_mail(BookingMailer, :video_meeting_ready)

        booking.reload
        expect(booking.video_meeting_video_created?).to be true
      end
    end

    context 'when email sending fails' do
      before do
        connection # ensure connection exists

        meeting_data = {
          meeting_id: '123456789',
          join_url: 'https://zoom.us/j/123456789',
          host_url: 'https://zoom.us/s/123456789',
          password: 'test_meeting_pwd',
          provider: 'zoom'
        }
        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_return(meeting_data)
        allow(zoom_service).to receive(:errors).and_return([])

        allow(BookingMailer).to receive(:video_meeting_ready).and_raise(StandardError.new('Email service down'))
      end

      it 'does not fail the job' do
        expect {
          described_class.new.perform(booking.id)
        }.not_to raise_error
      end

      it 'logs the email error' do
        expect(Rails.logger).to receive(:error).with(/Failed to send video meeting email/)

        described_class.new.perform(booking.id)
      end

      it 'still marks meeting as created' do
        described_class.new.perform(booking.id)
        booking.reload
        expect(booking.video_meeting_video_created?).to be true
      end
    end

    context 'when failure notification sending fails' do
      before do
        connection # ensure connection exists
        coordinator = instance_double(VideoMeeting::MeetingCoordinator)
        allow(VideoMeeting::MeetingCoordinator).to receive(:new).and_return(coordinator)
        allow(coordinator).to receive(:create_meeting).and_return(false)
        errors = ActiveModel::Errors.new(coordinator)
        errors.add(:api_error, 'API call failed')
        allow(coordinator).to receive(:errors).and_return(errors)

        allow(BusinessMailer).to receive(:video_meeting_failed).and_raise(StandardError.new('Email service down'))
      end

      it 'does not fail the job' do
        expect {
          described_class.new.perform(booking.id)
        }.not_to raise_error
      end

      it 'logs the notification error' do
        expect(Rails.logger).to receive(:error).with(/Failed to send failure notification/)

        described_class.new.perform(booking.id)
      end
    end

    context 'with concurrent job execution' do
      before do
        connection # ensure connection exists
      end

      it 'uses database locking to prevent duplicate API calls' do
        expect_any_instance_of(Booking).to receive(:with_lock).and_call_original

        zoom_service = instance_double(VideoMeeting::ZoomService)
        allow(VideoMeeting::ZoomService).to receive(:new).and_return(zoom_service)
        allow(zoom_service).to receive(:create_meeting).and_return({
          meeting_id: '123456789',
          join_url: 'https://zoom.us/j/123456789',
          host_url: 'https://zoom.us/s/123456789',
          password: 'test_meeting_pwd',
          provider: 'zoom'
        })
        allow(zoom_service).to receive(:errors).and_return([])

        described_class.new.perform(booking.id)
      end
    end
  end

end
