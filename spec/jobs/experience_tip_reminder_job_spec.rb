require 'rails_helper'

RSpec.describe ExperienceTipReminderJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:business) { create(:business, tip_mailer_if_no_tip_received: true) }
  let(:service) { create(:service, business: business, service_type: :standard, tips_enabled: true, tip_mailer_if_no_tip_received: true) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:booking) { create(:booking, business: business, service: service, tenant_customer: tenant_customer, status: :completed, start_time: 3.hours.ago, end_time: 2.hours.ago) }

  before do
    ActsAsTenant.current_tenant = business
  end

  describe "#perform" do
    context "with eligible booking" do
      it "sends tip reminder email" do
        expect(ExperienceMailer).to receive(:tip_reminder).with(booking).and_return(double(deliver_now: true))
        
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
        expect(Rails.logger).to receive(:info).with("Tip reminder sent for booking #{booking.id} (service type: #{booking.service.service_type})")
        
        perform_enqueued_jobs do
          ExperienceTipReminderJob.perform_later(booking.id)
        end
      end
    end

    context "with ineligible booking" do
      context "when booking is not completed" do
        let(:booking) { create(:booking, business: business, service: service, tenant_customer: tenant_customer, status: :confirmed, start_time: 1.hour.from_now, end_time: 2.hours.from_now) }
        let(:service) { create(:service, business: business, service_type: :standard, tips_enabled: true, tip_mailer_if_no_tip_received: true) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when business has tip mailer disabled" do
        let(:business) { create(:business, tip_mailer_if_no_tip_received: false) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when service has tips disabled" do
        let(:service) { create(:service, business: business, service_type: :standard, tips_enabled: false, tip_mailer_if_no_tip_received: true) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when service has tip mailer disabled" do
        let(:service) { create(:service, business: business, service_type: :standard, tips_enabled: true, tip_mailer_if_no_tip_received: false) }

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when tip already exists" do
        before do
          create(:tip, business: business, booking: booking, tenant_customer: tenant_customer)
        end

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when tip was received on initial payment (invoice)" do
        let(:invoice) { create(:invoice, business: business, tip_received_on_initial_payment: true, tip_amount_received_initially: 10.00) }
        
        before do
          booking.update!(invoice: invoice)
        end

        it "does not send reminder" do
          expect(ExperienceMailer).not_to receive(:tip_reminder)
          
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        end
      end

      context "when tip was received on initial payment (order)" do
        let(:order) { create(:order, business: business, booking: booking, tip_received_on_initial_payment: true, tip_amount_received_initially: 15.00) }
        
        before do
          order # Create the order associated with the booking
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
          booking.update!(tip_reminder_sent_at: 1.hour.ago)
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
        expect(Rails.logger).to receive(:error).with("Failed to send tip reminder for booking #{booking.id}: Email failed")
        
        expect {
          perform_enqueued_jobs do
            ExperienceTipReminderJob.perform_later(booking.id)
          end
        }.to raise_error(Minitest::UnexpectedError)
      end
    end
  end
end 