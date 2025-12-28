# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalyticsIngestionJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:session_id) { SecureRandom.uuid }
  let(:visitor_fingerprint) { SecureRandom.hex(16) }

  let(:base_event) do
    {
      type: 'page_view',
      timestamp: Time.current.iso8601,
      session_id: session_id,
      visitor_fingerprint: visitor_fingerprint,
      data: {
        'page_path' => '/services',
        'page_type' => 'services',
        'page_title' => 'Our Services',
        'referrer_url' => 'https://google.com',
        'referrer_domain' => 'google.com',
        'device_type' => 'desktop',
        'browser' => 'Chrome',
        'os' => 'Windows'
      }
    }
  end

  let(:request_metadata) do
    {
      ip_address: '192.168.1.xxx',
      user_agent: 'Mozilla/5.0',
      host: 'mybiz.bizblasts.com'
    }
  end

  describe '#perform' do
    context 'with valid page view event' do
      it 'creates a visitor session' do
        expect {
          described_class.perform_now(
            business_id: business.id,
            events: [base_event],
            request_metadata: request_metadata
          )
        }.to change(VisitorSession, :count).by(1)
      end

      it 'creates a page view record' do
        expect {
          described_class.perform_now(
            business_id: business.id,
            events: [base_event],
            request_metadata: request_metadata
          )
        }.to change(PageView, :count).by(1)
      end

      it 'sets the page view attributes correctly' do
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )

        page_view = PageView.last
        expect(page_view.page_path).to eq('/services')
        expect(page_view.page_type).to eq('services')
        expect(page_view.referrer_domain).to eq('google.com')
        expect(page_view.device_type).to eq('desktop')
        expect(page_view.is_entry_page).to be true
      end

      it 'marks first page view as entry page' do
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )

        page_view = PageView.last
        expect(page_view.is_entry_page).to be true

        session = VisitorSession.find_by(session_id: session_id)
        expect(session.entry_page).to eq('/services')
      end

      it 'does not mark subsequent page views as entry pages' do
        # First page view
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )

        # Second page view
        second_event = base_event.deep_dup
        second_event[:data]['page_path'] = '/about'

        described_class.perform_now(
          business_id: business.id,
          events: [second_event],
          request_metadata: request_metadata
        )

        page_views = PageView.order(:created_at)
        expect(page_views.first.is_entry_page).to be true
        expect(page_views.last.is_entry_page).to be false
      end

      it 'increments session page view count' do
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )

        session = VisitorSession.find_by(session_id: session_id)
        expect(session.page_view_count).to eq(1)

        # Another page view
        described_class.perform_now(
          business_id: business.id,
          events: [base_event.deep_dup],
          request_metadata: request_metadata
        )

        session.reload
        expect(session.page_view_count).to eq(2)
      end
    end

    context 'with click event' do
      let(:click_event) do
        {
          type: 'click',
          timestamp: Time.current.iso8601,
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          data: {
            'element_type' => 'button',
            'element_text' => 'Book Now',
            'page_path' => '/services',
            'category' => 'booking',
            'action' => 'click'
          }
        }
      end

      before do
        # Create session first
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )
      end

      it 'creates a click event record' do
        expect {
          described_class.perform_now(
            business_id: business.id,
            events: [click_event],
            request_metadata: request_metadata
          )
        }.to change(ClickEvent, :count).by(1)
      end

      it 'sets click event attributes correctly' do
        described_class.perform_now(
          business_id: business.id,
          events: [click_event],
          request_metadata: request_metadata
        )

        click = ClickEvent.last
        expect(click.element_type).to eq('button')
        expect(click.element_text).to eq('Book Now')
        expect(click.category).to eq('booking')
      end

      it 'increments session click count' do
        described_class.perform_now(
          business_id: business.id,
          events: [click_event],
          request_metadata: request_metadata
        )

        session = VisitorSession.find_by(session_id: session_id)
        expect(session.click_count).to eq(1)
      end

      it 'marks booking clicks as conversion started' do
        booking_click = click_event.deep_dup
        booking_click[:data]['category'] = 'booking'
        booking_click[:data]['action'] = 'book'

        described_class.perform_now(
          business_id: business.id,
          events: [booking_click],
          request_metadata: request_metadata
        )

        click = ClickEvent.last
        expect(click.is_conversion).to be true
        expect(click.conversion_type).to eq('booking_started')
      end
    end

    context 'with conversion event' do
      let(:conversion_event) do
        {
          type: 'conversion',
          timestamp: Time.current.iso8601,
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          data: {
            'conversion_type' => 'booking_completed',
            'conversion_value' => 150.00,
            'page_path' => '/booking/confirmation'
          }
        }
      end

      before do
        # Create session first
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )
      end

      it 'marks session as converted' do
        described_class.perform_now(
          business_id: business.id,
          events: [conversion_event],
          request_metadata: request_metadata
        )

        session = VisitorSession.find_by(session_id: session_id)
        expect(session.converted).to be true
        expect(session.conversion_type).to eq('booking_completed')
        expect(session.conversion_value).to eq(150.00)
      end

      it 'creates a conversion click event record' do
        expect {
          described_class.perform_now(
            business_id: business.id,
            events: [conversion_event],
            request_metadata: request_metadata
          )
        }.to change(ClickEvent, :count).by(1)

        click = ClickEvent.last
        expect(click.is_conversion).to be true
        expect(click.element_type).to eq('conversion')
      end
    end

    context 'with page view update event' do
      let(:update_event) do
        {
          type: 'page_view_update',
          timestamp: Time.current.iso8601,
          session_id: session_id,
          visitor_fingerprint: visitor_fingerprint,
          data: {
            'page_path' => '/services',
            'time_on_page' => 45,
            'scroll_depth' => 75,
            'is_exit_page' => true
          }
        }
      end

      before do
        # Create initial page view
        described_class.perform_now(
          business_id: business.id,
          events: [base_event],
          request_metadata: request_metadata
        )
      end

      it 'updates page view engagement metrics' do
        described_class.perform_now(
          business_id: business.id,
          events: [update_event],
          request_metadata: request_metadata
        )

        page_view = PageView.last
        expect(page_view.time_on_page).to eq(45)
        expect(page_view.scroll_depth).to eq(75)
        expect(page_view.is_exit_page).to be true
      end

      it 'updates session exit page' do
        described_class.perform_now(
          business_id: business.id,
          events: [update_event],
          request_metadata: request_metadata
        )

        session = VisitorSession.find_by(session_id: session_id)
        expect(session.exit_page).to eq('/services')
      end
    end

    context 'with empty events' do
      it 'does not create any records' do
        expect {
          described_class.perform_now(
            business_id: business.id,
            events: [],
            request_metadata: request_metadata
          )
        }.not_to change(PageView, :count)
      end
    end

    context 'with nil business_id' do
      it 'uses business_id from event data' do
        event_with_business = base_event.deep_dup
        event_with_business[:business_id] = business.id

        expect {
          described_class.perform_now(
            business_id: nil,
            events: [event_with_business],
            request_metadata: request_metadata
          )
        }.to change(PageView, :count).by(1)
      end

      it 'skips events without valid business' do
        expect {
          described_class.perform_now(
            business_id: nil,
            events: [base_event],
            request_metadata: request_metadata
          )
        }.not_to change(PageView, :count)
      end
    end

    context 'with returning visitor' do
      it 'marks session as returning visitor' do
        # First visit
        first_session_id = SecureRandom.uuid
        first_event = base_event.deep_dup
        first_event[:session_id] = first_session_id

        described_class.perform_now(
          business_id: business.id,
          events: [first_event],
          request_metadata: request_metadata
        )

        # Second visit (same fingerprint, different session)
        second_session_id = SecureRandom.uuid
        second_event = base_event.deep_dup
        second_event[:session_id] = second_session_id

        described_class.perform_now(
          business_id: business.id,
          events: [second_event],
          request_metadata: request_metadata
        )

        second_session = VisitorSession.find_by(session_id: second_session_id)
        expect(second_session.is_returning_visitor).to be true
        expect(second_session.previous_session_count).to eq(1)
      end
    end

    context 'with concurrent session creation' do
      it 'handles race conditions gracefully' do
        # This simulates two workers trying to create the same session
        # First one succeeds, second one should find and use existing

        allow(VisitorSession).to receive(:create!).and_raise(
          ActiveRecord::RecordNotUnique.new('duplicate key')
        ).once.and_call_original

        allow_any_instance_of(ActiveRecord::Associations::CollectionProxy).to receive(:find_by!).and_return(
          create(:visitor_session, business: business, session_id: session_id)
        )

        expect {
          described_class.perform_now(
            business_id: business.id,
            events: [base_event],
            request_metadata: request_metadata
          )
        }.not_to raise_error
      end
    end

    context 'with unknown event type' do
      it 'logs warning and continues' do
        unknown_event = base_event.deep_dup
        unknown_event[:type] = 'unknown_type'

        expect(Rails.logger).to receive(:warn).with(/Unknown event type/)

        described_class.perform_now(
          business_id: business.id,
          events: [unknown_event],
          request_metadata: request_metadata
        )
      end
    end
  end

  describe 'queue configuration' do
    it 'uses the analytics queue' do
      expect(described_class.new.queue_name).to eq('analytics')
    end
  end
end
