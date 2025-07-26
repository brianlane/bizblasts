# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecureLogger, type: :service do
  describe '.sanitize_message' do
    it 'redacts email addresses' do
      message = 'User john.doe@example.com attempted login'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to eq('User joh***@*** attempted login')
    end

    it 'redacts phone numbers' do
      message = 'Contact phone: 555-123-4567'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to eq('Contact phone: ***-***-4567')
    end

    it 'redacts SSN' do
      message = 'SSN: 123-45-6789'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to eq('SSN: [REDACTED_SSN]')
    end

    it 'redacts credit card numbers' do
      message = 'Credit card: 4111-1111-1111-1111'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to eq('Credit card: [REDACTED_CREDIT_CARD]')
    end

    it 'redacts API keys' do
      message = 'API key: abc123def456ghi789jkl012'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to eq('API key: [REDACTED_API_KEY]')
    end

    it 'handles multiple sensitive data types' do
      message = 'User jane@test.com called 555-1234 with card 4111111111111111'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to include('jan***@***')
      expect(sanitized).to include('[REDACTED_CREDIT_CARD]')
      expect(sanitized).to include('***-***-1234')
    end

    it 'returns original message if no sensitive data found' do
      message = 'This is a safe log message'
      sanitized = SecureLogger.sanitize_message(message)
      expect(sanitized).to eq(message)
    end

    it 'handles nil input' do
      expect(SecureLogger.sanitize_message(nil)).to be_nil
    end

    it 'handles non-string input' do
      expect(SecureLogger.sanitize_message(123)).to eq(123)
    end
  end

  describe '.security_event' do
    let(:mock_mailer) { double('SecurityMailer') }
    let(:mock_mail) { double('Mail', deliver_later: true) }

    before do
      allow(SecurityMailer).to receive(:security_alert).and_return(mock_mail)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('ADMIN_EMAIL').and_return('admin@example.com')
    end

    it 'logs security events with sanitized data' do
      expect(Rails.logger).to receive(:warn).with(
        a_string_including('[SECURITY_EVENT] UNAUTHORIZED_ACCESS')
      )

      SecureLogger.security_event('unauthorized_access', {
        ip: '192.168.1.1',
        user_id: 123,
        email: 'user@example.com'
      })
    end

    it 'sends email alerts for critical events' do
      expect(SecurityMailer).to receive(:security_alert).with(
        hash_including(
          event_type: 'unauthorized_access',
          timestamp: an_instance_of(Time)
        )
      )

      SecureLogger.security_event('unauthorized_access', {
        ip: '192.168.1.1',
        user_id: 123
      })
    end

    it 'does not send email alerts for non-critical events' do
      expect(SecurityMailer).not_to receive(:security_alert)

      SecureLogger.security_event('info_event', {
        ip: '192.168.1.1',
        user_id: 123
      })
    end

    it 'handles mailer failures gracefully' do
      allow(SecurityMailer).to receive(:security_alert).and_raise(StandardError.new('Mail error'))
      expect(Rails.logger).to receive(:error).with(
        a_string_including('[SecureLogger] Failed to send security alert')
      )

      SecureLogger.security_event('unauthorized_access', {
        ip: '192.168.1.1',
        user_id: 123
      })
    end

    it 'skips email when ADMIN_EMAIL is not set' do
      allow(ENV).to receive(:[]).with('ADMIN_EMAIL').and_return(nil)
      expect(SecurityMailer).not_to receive(:security_alert)

      SecureLogger.security_event('unauthorized_access', {
        ip: '192.168.1.1',
        user_id: 123
      })
    end
  end

  describe 'logging methods' do
    it 'sanitizes messages in info logs' do
      expect(Rails.logger).to receive(:info).with('User: joh***@***')
      SecureLogger.info('User: john@example.com')
    end

    it 'sanitizes messages in warn logs' do
      expect(Rails.logger).to receive(:warn).with('User: joh***@***')
      SecureLogger.warn('User: john@example.com')
    end

    it 'sanitizes messages in error logs' do
      expect(Rails.logger).to receive(:error).with('User: joh***@***')
      SecureLogger.error('User: john@example.com')
    end

    it 'sanitizes messages in debug logs' do
      expect(Rails.logger).to receive(:debug).with('User: joh***@***')
      SecureLogger.debug('User: john@example.com')
    end
  end
end