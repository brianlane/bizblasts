require 'rails_helper'

RSpec.describe ExperienceTipReminderJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:business) { create(:business, tips_enabled: true) }
  let(:service) { create(:service, business: business, service_type: :experience, tips_enabled: true, min_bookings: 1, max_bookings: 10, spots: 10) }
  let(:booking) { create(:booking, business: business, service: service, status: :completed) }

  describe "#perform" do
    context "with eligible booking" do
      it "sends tip reminder email" do
        expect(ExperienceMailer).to receive(:tip_reminder).with(booking).and_call_original
        expect_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now)
        
        perform_enqueued_jobs do
          ExperienceTipReminderJob.perform_later(booking.id)
        end
      end

      it "updates tip_reminder_sent_at timestamp" do
        travel_to Time.current do
          allow(ExperienceMailer).to receive(:tip_reminder).and_return(double(deliver_now: true))
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
          
          expect(booking.reload.tip_reminder_sent_at).to be_within(1.second).of(Time.current)
        end
      end

      it "logs successful reminder" do
        allow(ExperienceMailer).to receive(:tip_reminder).and_return(double(deliver_now: true))
        expect(Rails.logger).to receive(:info).with("Experience tip reminder sent for booking #{booking.id}")
        
        perform_enqueued_jobs do
          ExperienceTipReminderJob.perform_later(booking.id)
        end
      end
    end

    context "with ineligible booking" do
      context "when booking is not completed" do
        let(:service) { create(:service, business: business, service_type: :experience, tips_enabled: true, min_bookings: 1, max_bookings: 10, spots: 10) }
        let(:booking) { create(:booking, business: business, service: service, status: :confirmed) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when service is not experience type" do
        let(:service) { create(:service, business: business, service_type: :standard, tips_enabled: true) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when service is not tip eligible" do
        let(:service) { create(:service, business: business, service_type: :experience, tips_enabled: false, min_bookings: 1, max_bookings: 10, spots: 10) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when business has tips disabled" do
        let(:business) { create(:business, tips_enabled: false) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when tip already exists" do
        before do
          create(:tip, booking: booking, business: business)
        end

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when reminder was sent recently" do
        before do
          booking.update_column(:tip_reminder_sent_at, 24.hours.ago)
        end

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end
    end

    context "when booking doesn't exist" do
      it "handles gracefully" do
        expect(ExperienceMailer).not_to receive(:tip_reminder)
        
        perform_enqueued_jobs do
          ExperienceTipReminderJob.perform_later(999999)
        end
      end
    end

    context "when email fails" do
      before do
        allow(ExperienceMailer).to receive(:tip_reminder).and_raise(StandardError.new("Email failed"))
      end

      it "logs error and re-raises" do
        expect(Rails.logger).to receive(:error).with("Failed to send experience tip reminder for booking #{booking.id}: Email failed")
        
        expect {
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        }.to raise_error(Minitest::UnexpectedError)
      end
    end
  end
end 