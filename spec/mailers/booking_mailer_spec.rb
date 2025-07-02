require 'rails_helper'

RSpec.describe BookingMailer, type: :mailer do
  let(:business) { create(:business, :subdomain_host) }
  let(:service) { create(:service, business: business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:booking) do
    create(:booking,
           business: business,
           service: service,
           staff_member: staff_member,
           tenant_customer: tenant_customer,
           start_time: 2.hours.from_now,
           end_time: 3.hours.from_now
    )
  end

  describe '#status_update' do
    let(:mail) { BookingMailer.status_update(booking) }

    before do
      # Assign instance variables that template expects
      booking.define_singleton_method(:status) { 'confirmed' }
    end

    it 'renders the headers' do
      expect(mail.subject).to include('Status Update')
      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.from).to be_present
    end

    it 'renders the body with booking details' do
      expect(mail.body.encoded).to include(service.name)
      expect(mail.body.encoded).to include(tenant_customer.first_name)
      expect(mail.body.encoded).to include(business.name)
    end

    it 'includes status badge' do
      expect(mail.body.encoded).to include('confirmed')
    end
  end

  describe '#cancellation' do
    let(:mail) { BookingMailer.cancellation(booking) }

    before do
      booking.update(status: 'cancelled', cancellation_reason: 'Test cancellation')
    end

    it 'renders the headers' do
      expect(mail.subject).to include('Cancelled')
      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.from).to be_present
    end

    it 'renders the body with cancellation details' do
      expect(mail.body.encoded).to include('cancelled')
      expect(mail.body.encoded).to include(service.name)
      expect(mail.body.encoded).to include(tenant_customer.first_name)
      expect(mail.body.encoded).to include(business.name)
    end

    it 'includes cancellation reason when provided' do
      booking.update(cancellation_reason: 'Manager override')
      mail = BookingMailer.cancellation(booking)
      expect(mail.body.encoded).to include('Manager override')
    end

    it 'includes refund information' do
      expect(mail.body.encoded).to include('refund')
      expect(mail.body.encoded).to include('3-5 business days')
    end
  end

  describe '#confirmation' do
    let(:mail) { BookingMailer.confirmation(booking) }

    before do
      booking.update(status: 'confirmed')
    end

    it 'renders the headers' do
      expect(mail.subject).to include('Booking Confirmation')
      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.from).to be_present
    end

    it 'renders the body with booking details' do
      expect(mail.body.encoded).to include(service.name)
      expect(mail.body.encoded).to include(staff_member.full_name) if staff_member.respond_to?(:full_name)
      expect(mail.body.encoded).to include(tenant_customer.full_name)
      expect(mail.body.encoded).to include(business.name)
      expect(mail.body.encoded).to include(booking.local_start_time.strftime('%A, %B %d, %Y'))
      expect(mail.body.encoded).to include(booking.local_start_time.strftime('%I:%M %p'))
      expect(mail.body.encoded).to include(booking.local_end_time.strftime('%I:%M %p'))
      expect(mail.body.encoded).to include(booking.duration.to_i.to_s)
    end

    it 'includes booking policy if present' do
      if business.booking_policy&.has_customer_visible_policies?
        expect(mail.body.encoded).to include('Booking Policy')
      end
    end
  end

  describe '#status_update as reschedule' do
    let(:mail) { BookingMailer.status_update(booking) }

    before do
      booking.define_singleton_method(:status) { 'rescheduled' }
    end

    it 'renders the headers' do
      expect(mail.subject).to include('Status Update')
      expect(mail.to).to eq([tenant_customer.email])
      expect(mail.from).to be_present
    end

    it 'renders the body with reschedule details' do
      expect(mail.body.encoded).to include(service.name)
      expect(mail.body.encoded).to include(tenant_customer.first_name)
      expect(mail.body.encoded).to include(business.name)
      expect(mail.body.encoded).to include('rescheduled').or include('Rescheduled')
    end

    it 'includes status badge for rescheduled' do
      expect(mail.body.encoded).to include('rescheduled').or include('Rescheduled')
    end
  end

  describe 'email template rendering' do
    it 'status_update template renders without errors' do
      expect { BookingMailer.status_update(booking).body }.not_to raise_error
    end

    it 'cancellation template renders without errors' do
      expect { BookingMailer.cancellation(booking).body }.not_to raise_error
    end

    it 'confirmation template renders without errors' do
      expect { BookingMailer.confirmation(booking).body }.not_to raise_error
    end

    it 'status_update template renders without errors for reschedule' do
      booking.define_singleton_method(:status) { 'rescheduled' }
      expect { BookingMailer.status_update(booking).body }.not_to raise_error
    end
  end
end 