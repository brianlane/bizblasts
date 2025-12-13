# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoMeeting::BaseService do
  let(:business) { create(:business) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:connection) do
    create(:video_meeting_connection,
           business: business,
           staff_member: staff_member,
           provider: :zoom,
           access_token: 'test_token',
           refresh_token: 'test_refresh',
           token_expires_at: 1.hour.from_now)
  end

  subject(:service) { described_class.new(connection) }

  describe '#initialize' do
    it 'sets connection' do
      expect(service.connection).to eq(connection)
    end

    it 'initializes empty errors' do
      expect(service.errors).to be_empty
    end
  end

  describe '#create_meeting' do
    it 'raises NotImplementedError' do
      booking = build(:booking)
      expect { service.create_meeting(booking) }.to raise_error(NotImplementedError)
    end
  end

  describe '#delete_meeting' do
    it 'raises NotImplementedError' do
      expect { service.delete_meeting('meeting_id') }.to raise_error(NotImplementedError)
    end
  end

  describe '#get_meeting' do
    it 'raises NotImplementedError' do
      expect { service.get_meeting('meeting_id') }.to raise_error(NotImplementedError)
    end
  end

  describe 'RETRYABLE_EXCEPTIONS' do
    it 'includes network timeout errors' do
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(Net::ReadTimeout)
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(Net::OpenTimeout)
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(Faraday::TimeoutError)
    end

    it 'includes connection errors' do
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(Errno::ECONNRESET)
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(Errno::ECONNREFUSED)
      expect(described_class::RETRYABLE_EXCEPTIONS).to include(Errno::ETIMEDOUT)
    end
  end

  describe '#ensure_valid_token!' do
    # Create a test subclass to access protected methods
    let(:test_service_class) do
      Class.new(described_class) do
        def test_ensure_valid_token!
          ensure_valid_token!
        end

        def test_handle_api_error(error)
          handle_api_error(error)
        end
      end
    end

    let(:test_service) { test_service_class.new(connection) }

    context 'when token is valid and not expiring soon' do
      it 'returns true' do
        expect(test_service.test_ensure_valid_token!).to be true
      end
    end

    context 'when token is expired' do
      before do
        connection.update!(token_expires_at: 1.hour.ago)
      end

      context 'with refresh token available' do
        it 'attempts to refresh the token' do
          oauth_handler = instance_double(VideoMeeting::OauthHandler)
          allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
          allow(oauth_handler).to receive(:refresh_token).with(connection).and_return(true)

          expect(test_service.test_ensure_valid_token!).to be true
        end
      end

      context 'without refresh token' do
        before do
          connection.update!(refresh_token: nil)
        end

        it 'returns false and adds error' do
          expect(test_service.test_ensure_valid_token!).to be false
          expect(test_service.errors[:token_expired]).to be_present
        end
      end
    end

    context 'when token is expiring soon' do
      before do
        connection.update!(token_expires_at: 3.minutes.from_now)
      end

      it 'proactively refreshes the token' do
        oauth_handler = instance_double(VideoMeeting::OauthHandler)
        allow(VideoMeeting::OauthHandler).to receive(:new).and_return(oauth_handler)
        allow(oauth_handler).to receive(:refresh_token).with(connection).and_return(true)

        expect(test_service.test_ensure_valid_token!).to be true
      end
    end
  end

  describe '#handle_api_error' do
    let(:test_service_class) do
      Class.new(described_class) do
        def test_handle_api_error(error)
          handle_api_error(error)
        end
      end
    end

    let(:test_service) { test_service_class.new(connection) }

    context 'with non-retryable error' do
      it 'logs error and does not re-raise' do
        error = StandardError.new('API Error')
        expect(Rails.logger).to receive(:error).at_least(:once)

        expect { test_service.test_handle_api_error(error) }.not_to raise_error
        expect(test_service.errors[:api_error]).to include('API Error')
      end
    end

    context 'with retryable error' do
      it 're-raises Net::ReadTimeout' do
        error = Net::ReadTimeout.new
        expect { test_service.test_handle_api_error(error) }.to raise_error(Net::ReadTimeout)
      end

      it 're-raises Errno::ECONNRESET' do
        error = Errno::ECONNRESET.new
        expect { test_service.test_handle_api_error(error) }.to raise_error(Errno::ECONNRESET)
      end
    end
  end
end
