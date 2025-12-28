# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::SessionAggregationJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }

  describe '#perform' do
    context 'with inactive sessions' do
      let!(:inactive_session) do
        session = create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 3
        )
        # Create page views for this session
        3.times do |i|
          create(:page_view,
            business: business,
            session_id: session.session_id,
            page_path: "/page#{i + 1}",
            created_at: 35.minutes.ago
          )
        end
        session
      end

      it 'closes inactive sessions' do
        described_class.perform_now

        inactive_session.reload
        expect(inactive_session.session_end).to be_present
      end

      it 'calculates session duration' do
        described_class.perform_now

        inactive_session.reload
        expect(inactive_session.duration_seconds).to be > 0
      end

      it 'sets exit page' do
        described_class.perform_now

        inactive_session.reload
        expect(inactive_session.exit_page).to be_present
      end

      it 'marks single page sessions as bounces' do
        bounce_session = create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 1
        )
        create(:page_view, business: business, session_id: bounce_session.session_id, created_at: 35.minutes.ago)

        described_class.perform_now

        bounce_session.reload
        expect(bounce_session.is_bounce).to be true
      end

      it 'does not mark multi-page sessions as bounces' do
        described_class.perform_now

        inactive_session.reload
        expect(inactive_session.is_bounce).to be false
      end

      it 'marks last page view as exit page' do
        described_class.perform_now

        last_page_view = inactive_session.page_views.order(created_at: :desc).first
        expect(last_page_view.is_exit_page).to be true
      end
    end

    context 'with active sessions' do
      let!(:active_session) do
        session = create(:visitor_session,
          business: business,
          session_start: 10.minutes.ago,
          session_end: nil,
          page_view_count: 2
        )
        # Create recent page views
        2.times do |i|
          create(:page_view,
            business: business,
            session_id: session.session_id,
            page_path: "/active#{i + 1}",
            created_at: 5.minutes.ago
          )
        end
        session
      end

      it 'does not close active sessions' do
        described_class.perform_now

        active_session.reload
        expect(active_session.session_end).to be_nil
      end
    end

    context 'with click events determining last activity' do
      let!(:session_with_clicks) do
        create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 1
        )
      end

      before do
        # Page view is old
        create(:page_view,
          business: business,
          session_id: session_with_clicks.session_id,
          created_at: 1.hour.ago
        )
        # Click event is recent
        create(:click_event,
          business: business,
          session_id: session_with_clicks.session_id,
          created_at: 5.minutes.ago
        )
      end

      it 'considers click events for last activity' do
        described_class.perform_now

        session_with_clicks.reload
        # Session should NOT be closed because click event is recent
        expect(session_with_clicks.session_end).to be_nil
      end
    end

    context 'with sessions having only click events' do
      let!(:click_only_session) do
        create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 0
        )
      end

      before do
        create(:click_event,
          business: business,
          session_id: click_only_session.session_id,
          created_at: 40.minutes.ago
        )
      end

      it 'closes sessions with only old click events' do
        described_class.perform_now

        click_only_session.reload
        expect(click_only_session.session_end).to be_present
      end

      it 'uses click event time for session end' do
        described_class.perform_now

        click_only_session.reload
        # Session end should be based on the click event time
        expect(click_only_session.session_end).to be_within(1.minute).of(40.minutes.ago)
      end
    end

    context 'with already closed sessions' do
      let!(:closed_session) do
        create(:visitor_session,
          business: business,
          session_start: 3.hours.ago,
          session_end: 2.hours.ago,
          duration_seconds: 3600
        )
      end

      it 'does not re-process closed sessions' do
        original_end = closed_session.session_end

        described_class.perform_now

        closed_session.reload
        expect(closed_session.session_end).to eq(original_end)
      end
    end

    context 'with multiple businesses' do
      let(:other_business) { create(:business) }

      let!(:session1) do
        session = create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 2
        )
        create(:page_view, business: business, session_id: session.session_id, created_at: 35.minutes.ago)
        session
      end

      let!(:session2) do
        session = create(:visitor_session,
          business: other_business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 2
        )
        create(:page_view, business: other_business, session_id: session.session_id, created_at: 35.minutes.ago)
        session
      end

      it 'processes sessions for all active businesses' do
        described_class.perform_now

        session1.reload
        session2.reload

        expect(session1.session_end).to be_present
        expect(session2.session_end).to be_present
      end
    end

    context 'with nil page_view_count' do
      let!(:nil_count_session) do
        create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil
        )
      end

      before do
        # Manually set page_view_count to nil to simulate edge case
        nil_count_session.update_column(:page_view_count, nil)
        create(:page_view,
          business: business,
          session_id: nil_count_session.session_id,
          created_at: 35.minutes.ago
        )
      end

      it 'handles nil page_view_count gracefully' do
        expect {
          described_class.perform_now
        }.not_to raise_error

        nil_count_session.reload
        expect(nil_count_session.is_bounce).to be true
      end
    end

    context 'when business processing fails' do
      let!(:session) do
        s = create(:visitor_session,
          business: business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 2
        )
        create(:page_view, business: business, session_id: s.session_id, created_at: 35.minutes.ago)
        s
      end

      it 'logs error and continues with other businesses' do
        other_business = create(:business)
        other_session = create(:visitor_session,
          business: other_business,
          session_start: 2.hours.ago,
          session_end: nil,
          page_view_count: 2
        )
        create(:page_view, business: other_business, session_id: other_session.session_id, created_at: 35.minutes.ago)

        # Make first business fail
        allow_any_instance_of(VisitorSession).to receive(:update!).and_raise(StandardError.new('Test error')).once.and_call_original

        expect(Rails.logger).to receive(:error).at_least(:once)

        # Should not raise error
        expect {
          described_class.perform_now
        }.not_to raise_error
      end
    end
  end

  describe 'queue configuration' do
    it 'uses the analytics queue' do
      expect(described_class.new.queue_name).to eq('analytics')
    end
  end

  describe 'SESSION_TIMEOUT constant' do
    it 'is set to 30 minutes' do
      expect(described_class::SESSION_TIMEOUT).to eq(30)
    end
  end
end
