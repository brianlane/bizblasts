# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VisitorSession, type: :model do
  let(:business) { create(:business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'validations' do
    it 'requires visitor_fingerprint' do
      session = build(:visitor_session, business: business, visitor_fingerprint: nil)
      expect(session).not_to be_valid
    end

    it 'requires session_id to be unique' do
      create(:visitor_session, business: business, session_id: 'unique-id')
      duplicate = build(:visitor_session, business: business, session_id: 'unique-id')
      expect(duplicate).not_to be_valid
    end

    it 'is valid with required attributes' do
      session = build(:visitor_session, business: business)
      expect(session).to be_valid
    end
  end

  describe 'scopes' do
    it 'filters bounced sessions' do
      create(:visitor_session, :bounce, business: business)
      create(:visitor_session, :engaged, business: business)
      
      expect(VisitorSession.bounced.count).to eq(1)
      expect(VisitorSession.engaged.count).to eq(1)
    end

    it 'filters converted sessions' do
      create(:visitor_session, :converted_booking, business: business)
      create(:visitor_session, business: business)
      
      expect(VisitorSession.converted.count).to eq(1)
    end

    it 'filters returning visitors' do
      create(:visitor_session, :returning, business: business)
      create(:visitor_session, :new_visitor, business: business)
      
      expect(VisitorSession.returning_visitors.count).to eq(1)
      expect(VisitorSession.new_visitors.count).to eq(1)
    end
  end

  describe 'class methods' do
    describe '.bounce_rate' do
      it 'calculates correct bounce rate' do
        create(:visitor_session, :bounce, business: business)
        create(:visitor_session, :bounce, business: business)
        create(:visitor_session, :engaged, business: business)
        
        # 2 bounces out of 3 sessions = 66.67%
        expect(VisitorSession.bounce_rate).to be_within(0.1).of(66.67)
      end

      it 'returns 0 when no sessions exist' do
        expect(VisitorSession.bounce_rate).to eq(0.0)
      end
    end

    describe '.average_session_duration' do
      it 'calculates average duration' do
        create(:visitor_session, business: business, duration_seconds: 60)
        create(:visitor_session, business: business, duration_seconds: 120)
        
        expect(VisitorSession.average_session_duration).to eq(90)
      end
    end
  end

  describe 'instance methods' do
    describe '#end_session!' do
      it 'updates session end time and metrics' do
        session = create(:visitor_session, business: business, page_view_count: 3)
        
        session.end_session!
        
        expect(session.session_end).to be_present
        expect(session.is_bounce).to be false
      end

      it 'marks as bounce when only 1 page view' do
        session = create(:visitor_session, business: business, page_view_count: 1)
        
        session.end_session!
        
        expect(session.is_bounce).to be true
      end
    end

    describe '#mark_converted!' do
      it 'updates conversion fields' do
        session = create(:visitor_session, business: business)
        
        session.mark_converted!('booking', 100.0)
        
        expect(session.converted).to be true
        expect(session.conversion_type).to eq('booking')
        expect(session.conversion_value).to eq(100.0)
        expect(session.conversion_time).to be_present
      end
    end

    describe '#duration_formatted' do
      it 'formats duration in minutes and seconds' do
        session = build(:visitor_session, duration_seconds: 125)
        expect(session.duration_formatted).to eq('2m 5s')
      end

      it 'returns seconds only for short durations' do
        session = build(:visitor_session, duration_seconds: 45)
        expect(session.duration_formatted).to eq('45s')
      end

      it 'returns N/A for nil duration' do
        session = build(:visitor_session, duration_seconds: nil)
        expect(session.duration_formatted).to eq('N/A')
      end
    end
  end
end

