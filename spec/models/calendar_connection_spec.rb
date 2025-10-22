# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarConnection, type: :model do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }

  describe 'associations' do
    it { should belong_to(:business) }
    it { should belong_to(:staff_member) }
    it { should have_many(:calendar_event_mappings).dependent(:destroy) }
    it { should have_many(:external_calendar_events).dependent(:destroy) }
    it { should have_many(:bookings).through(:calendar_event_mappings) }
  end

  describe 'validations' do
    subject do
      CalendarConnection.new(
        business: business,
        staff_member: staff_member,
        provider: :google,
        access_token: 'test_token',
        active: true
      )
    end

    it { should validate_presence_of(:business_id) }
    it { should validate_presence_of(:staff_member_id) }
    it { should validate_presence_of(:provider) }
    it { should validate_inclusion_of(:active).in_array([true, false]) }
  end

  describe 'OAuth provider validations' do
    context 'when provider is google' do
      it 'requires access_token' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :google,
          active: true
        )
        expect(connection.valid?).to be false
        expect(connection.errors[:access_token]).to include("can't be blank")
      end
    end

    context 'when provider is microsoft' do
      it 'requires access_token' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :microsoft,
          active: true
        )
        expect(connection.valid?).to be false
        expect(connection.errors[:access_token]).to include("can't be blank")
      end
    end
  end

  describe 'CalDAV provider validations' do
    context 'when provider is caldav' do
      it 'requires caldav_username' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_password: 'password',
          active: true
        )
        expect(connection.valid?).to be false
        expect(connection.errors[:caldav_username]).to include("can't be blank")
      end

      it 'requires caldav_password' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@example.com',
          active: true
        )
        expect(connection.valid?).to be false
        expect(connection.errors[:caldav_password]).to include("can't be blank")
      end
    end
  end

  describe '#has_calendar_permissions?' do
    context 'with Google Calendar provider' do
      it 'returns true when exact calendar scope is present' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :google,
          access_token: 'token',
          scopes: 'https://www.googleapis.com/auth/calendar',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be true
      end

      it 'returns true when exact calendar scope is one of multiple scopes' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :google,
          access_token: 'token',
          scopes: 'https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/calendar,https://www.googleapis.com/auth/userinfo.profile',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be true
      end

      context 'security: prevents OAuth scope substring injection (CWE-20)' do
        it 'rejects scope with calendar scope as substring in URL' do
          # Attack: embed the valid scope URL in a malicious URL
          connection = CalendarConnection.new(
            business: business,
            staff_member: staff_member,
            provider: :google,
            access_token: 'token',
            scopes: 'https://evil.com?redirect=https://www.googleapis.com/auth/calendar',
            active: true
          )
          expect(connection.has_calendar_permissions?).to be false
        end

        it 'rejects scope with calendar scope embedded in path' do
          connection = CalendarConnection.new(
            business: business,
            staff_member: staff_member,
            provider: :google,
            access_token: 'token',
            scopes: 'https://attacker.net/https://www.googleapis.com/auth/calendar',
            active: true
          )
          expect(connection.has_calendar_permissions?).to be false
        end

        it 'rejects scope that contains calendar scope but has additional path' do
          connection = CalendarConnection.new(
            business: business,
            staff_member: staff_member,
            provider: :google,
            access_token: 'token',
            scopes: 'https://www.googleapis.com/auth/calendar/malicious',
            active: true
          )
          expect(connection.has_calendar_permissions?).to be false
        end

        it 'rejects scope with extra prefix before calendar scope' do
          connection = CalendarConnection.new(
            business: business,
            staff_member: staff_member,
            provider: :google,
            access_token: 'token',
            scopes: 'evil-https://www.googleapis.com/auth/calendar',
            active: true
          )
          expect(connection.has_calendar_permissions?).to be false
        end

        it 'rejects multiple scopes where none exactly match' do
          connection = CalendarConnection.new(
            business: business,
            staff_member: staff_member,
            provider: :google,
            access_token: 'token',
            scopes: 'https://www.googleapis.com/auth/userinfo.email,https://evil.com/auth/calendar,https://www.googleapis.com/auth/userinfo.profile',
            active: true
          )
          expect(connection.has_calendar_permissions?).to be false
        end
      end

      it 'returns false when calendar scope is missing' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :google,
          access_token: 'token',
          scopes: 'https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/userinfo.profile',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be false
      end

      it 'returns false when scopes is blank' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :google,
          access_token: 'token',
          scopes: '',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be false
      end

      it 'returns false when scopes is nil' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :google,
          access_token: 'token',
          scopes: nil,
          active: true
        )
        expect(connection.has_calendar_permissions?).to be false
      end
    end

    context 'with Microsoft Calendar provider' do
      it 'returns true when Calendars scope is present' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :microsoft,
          access_token: 'token',
          scopes: 'Calendars.ReadWrite',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be true
      end

      it 'returns true when scope contains Calendars' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :microsoft,
          access_token: 'token',
          scopes: 'User.Read,Calendars.ReadWrite,Mail.Read',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be true
      end

      it 'returns false when Calendars scope is missing' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :microsoft,
          access_token: 'token',
          scopes: 'User.Read,Mail.Read',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be false
      end
    end

    context 'with CalDAV provider' do
      it 'always returns true for CalDAV (no OAuth scopes)' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@example.com',
          caldav_password: 'password',
          active: true
        )
        expect(connection.has_calendar_permissions?).to be true
      end

      it 'returns true even without scopes for CalDAV' do
        connection = CalendarConnection.new(
          business: business,
          staff_member: staff_member,
          provider: :caldav,
          caldav_username: 'user@example.com',
          caldav_password: 'password',
          scopes: nil,
          active: true
        )
        expect(connection.has_calendar_permissions?).to be true
      end
    end
  end

  describe '#provider_display_name' do
    it 'returns "Google Calendar" for google provider' do
      connection = CalendarConnection.new(provider: :google)
      expect(connection.provider_display_name).to eq('Google Calendar')
    end

    it 'returns "Microsoft Outlook" for microsoft provider' do
      connection = CalendarConnection.new(provider: :microsoft)
      expect(connection.provider_display_name).to eq('Microsoft Outlook')
    end

    it 'returns caldav provider display name for caldav provider' do
      connection = CalendarConnection.new(provider: :caldav, caldav_provider: 'icloud')
      expect(connection.provider_display_name).to eq('iCloud Calendar')
    end
  end

  describe '#caldav_provider_display_name' do
    it 'returns "iCloud Calendar" for icloud provider' do
      connection = CalendarConnection.new(caldav_provider: 'icloud')
      expect(connection.caldav_provider_display_name).to eq('iCloud Calendar')
    end

    it 'returns "Nextcloud Calendar" for nextcloud provider' do
      connection = CalendarConnection.new(caldav_provider: 'nextcloud')
      expect(connection.caldav_provider_display_name).to eq('Nextcloud Calendar')
    end

    it 'returns "CalDAV Calendar" for generic provider' do
      connection = CalendarConnection.new(caldav_provider: 'generic')
      expect(connection.caldav_provider_display_name).to eq('CalDAV Calendar')
    end

    it 'returns "CalDAV Calendar" for unknown provider' do
      connection = CalendarConnection.new(caldav_provider: 'unknown')
      expect(connection.caldav_provider_display_name).to eq('CalDAV Calendar')
    end

    it 'returns "CalDAV Calendar" when caldav_provider is nil' do
      connection = CalendarConnection.new(caldav_provider: nil)
      expect(connection.caldav_provider_display_name).to eq('CalDAV Calendar')
    end
  end

  describe '#token_expired?' do
    it 'returns false when token_expires_at is blank' do
      connection = CalendarConnection.new(token_expires_at: nil)
      expect(connection.token_expired?).to be false
    end

    it 'returns true when token_expires_at is in the past' do
      connection = CalendarConnection.new(token_expires_at: 1.hour.ago)
      expect(connection.token_expired?).to be true
    end

    it 'returns false when token_expires_at is in the future' do
      connection = CalendarConnection.new(token_expires_at: 1.hour.from_now)
      expect(connection.token_expired?).to be false
    end
  end

  describe '#needs_refresh?' do
    it 'returns true when token is expired and refresh_token is present' do
      connection = CalendarConnection.new(
        token_expires_at: 1.hour.ago,
        refresh_token: 'refresh_token'
      )
      expect(connection.needs_refresh?).to be true
    end

    it 'returns false when token is expired but refresh_token is missing' do
      connection = CalendarConnection.new(
        token_expires_at: 1.hour.ago,
        refresh_token: nil
      )
      expect(connection.needs_refresh?).to be false
    end

    it 'returns false when token is not expired' do
      connection = CalendarConnection.new(
        token_expires_at: 1.hour.from_now,
        refresh_token: 'refresh_token'
      )
      expect(connection.needs_refresh?).to be false
    end
  end

  describe '#sync_scopes' do
    it 'returns empty array when scopes is blank' do
      connection = CalendarConnection.new(scopes: nil)
      expect(connection.sync_scopes).to eq([])
    end

    it 'splits scopes by comma' do
      connection = CalendarConnection.new(
        scopes: 'scope1,scope2,scope3'
      )
      expect(connection.sync_scopes).to eq(['scope1', 'scope2', 'scope3'])
    end

    it 'strips whitespace from scopes' do
      connection = CalendarConnection.new(
        scopes: 'scope1, scope2 , scope3'
      )
      expect(connection.sync_scopes).to eq(['scope1', 'scope2', 'scope3'])
    end
  end

  describe '#sync_scopes=' do
    it 'joins array of scopes with comma' do
      connection = CalendarConnection.new
      connection.sync_scopes = ['scope1', 'scope2', 'scope3']
      expect(connection.scopes).to eq('scope1,scope2,scope3')
    end

    it 'handles single scope' do
      connection = CalendarConnection.new
      connection.sync_scopes = ['scope1']
      expect(connection.scopes).to eq('scope1')
    end

    it 'handles empty array' do
      connection = CalendarConnection.new
      connection.sync_scopes = []
      expect(connection.scopes).to eq('')
    end
  end
end
