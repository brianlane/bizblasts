# frozen_string_literal: true

require 'rails_helper'
require 'nokogiri'

RSpec.describe DomainMailer, type: :mailer do
  # Helper to extract plain-text from HTML body across all examples
  def body_text(mail)
    Nokogiri::HTML(mail.body.decoded).text.squeeze(" \n")
  end

  let(:business) { create(:business, name: 'Test Business', hostname: 'example.com') }
  let(:user) { create(:user, email: 'owner@example.com', first_name: 'John', business: business) }

  before do
    ENV['SUPPORT_EMAIL'] = 'bizblaststeam@gmail.com'
  end

  after do
    ENV.delete('SUPPORT_EMAIL')
  end

  describe '#setup_instructions' do
    let(:mail) { described_class.setup_instructions(business, user) }

    it 'renders the headers' do
      expect(mail.subject).to eq('Custom Domain Setup Instructions for Test Business')
      expect(mail.to).to eq(['owner@example.com'])
      expect(mail.from).to eq([ENV['MAILER_EMAIL']])
    end

    it 'assigns instance variables' do
      expect(body_text(mail)).to include(business.hostname)
      expect(body_text(mail)).to include(user.first_name)
    end

    it 'includes DNS setup instructions for both A and CNAME records' do
      t = body_text(mail)
      expect(t).to include('A record')
      expect(t).to include('CNAME record')
      expect(t).to include('Type: A')
      expect(t).to include('Type: CNAME')
      expect(t).to include('216.24.57.1')
      expect(t).to match(/localhost|[a-z0-9\-]+\.bizblasts\.com/)
    end

    it 'includes registrar-specific instructions' do
      text = body_text(mail)
      %w[GoDaddy Namecheap Cloudflare].each { |provider| expect(text).to include(provider) }
    end

    it 'includes monitoring information' do
      text = body_text(mail)
      %w[monitor minutes hour].each { |word| expect(text).to include(word) }
    end

    it 'includes support contact information' do
      expect(body_text(mail)).to include('bizblaststeam@gmail.com')
    end

    context 'with www subdomain' do
      before { business.update!(tier: :premium, host_type: :custom_domain, hostname: 'www.example.com') }

      it 'includes both @ and www in DNS instructions' do
        text = body_text(mail)
        expect(text).to include('Name/Host: @')
        expect(text).to include('Name/Host: www')
      end
    end

    context 'with root domain' do
      it 'includes both @ and www in DNS instructions' do
        text = body_text(mail)
        expect(text).to include('Name/Host: @')
        expect(text).to include('Name/Host: www')
      end
    end

    context 'in development environment' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it 'uses localhost as target' do
        expect(body_text(mail)).to include('localhost')
      end
    end
  end

  describe '#activation_success' do
    let(:mail) { described_class.activation_success(business, user) }

    it 'renders the headers' do
      expect(mail.subject).to eq('🎉 Your custom domain example.com is now active!')
      expect(mail.to).to eq(['owner@example.com'])
    end

    it 'includes congratulations message' do
      expect(body_text(mail)).to include('Congratulations')
      expect(body_text(mail)).to include('successfully activated')
    end

    it 'includes domain URL' do
      t = body_text(mail)
      expect(t).to include('example.com')
      expect(t).to include('Visit Your Site')
    end

    it 'includes feature benefits' do
      text = body_text(mail)
      %w[SSL Automatic SEO].each { |word| expect(text).to include(word) }
    end

    it 'includes update instructions' do
      text = body_text(mail)
      %w[Google Social Business].each { |word| expect(text).to include(word) }
    end

    it 'mentions automatic redirects' do
      expect(body_text(mail)).to include('redirect')
    end
  end

  describe '#timeout_help' do
    let(:mail) { described_class.timeout_help(business, user) }

    it 'renders the headers' do
      expect(mail.subject).to eq('Help needed: Custom domain setup for example.com')
      expect(mail.to).to eq(['owner@example.com'])
    end

    it 'explains timeout situation' do
      expect(body_text(mail)).to include('past hour')
      expect(body_text(mail)).to include("haven't detected")
      expect(body_text(mail)).to include('CNAME record')
    end

    it 'includes troubleshooting steps' do
      expect(body_text(mail)).to include('Double-check')
      expect(body_text(mail)).to include('Common issues')
      expect(body_text(mail)).to include('DNS propagation')
    end

    it 'provides DNS configuration details' do
      text = body_text(mail)
      expect(text).to match(/localhost|[a-z0-9\-]+\.bizblasts\.com/)
    end

    it 'includes registrar-specific guides' do
      expect(body_text(mail)).to include('GoDaddy')
      expect(body_text(mail)).to include('Namecheap')
      expect(body_text(mail)).to include('Google Domains')
    end

    it 'provides support contact' do
      expect(body_text(mail)).to include('Get Help Now')
      expect(body_text(mail)).to include('bizblaststeam@gmail.com')
      expect(body_text(mail)).to include('Need immediate assistance')
    end

    it 'explains next steps' do
      expect(body_text(mail)).to include('Contact support')
      expect(body_text(mail)).to include('Fix the CNAME')
      expect(body_text(mail)).to include('Try later')
    end
  end

  describe '#monitoring_restarted' do
    let(:mail) { described_class.monitoring_restarted(business, user) }

    it 'renders the headers' do
      expect(mail.subject).to eq('Domain monitoring restarted for example.com')
      expect(mail.to).to eq(['owner@example.com'])
    end

    it 'explains monitoring restart' do
      expect(mail.body.encoded).to include('restarted monitoring')
      expect(mail.body.encoded).to include('check every 5 minutes')
      expect(mail.body.encoded).to include('next hour')
    end

    it 'includes current status information' do
      expect(body_text(mail)).to include('example.com')
      expect(body_text(mail)).to include('Business: Test Business')
      expect(body_text(mail)).to include('Status: Monitoring Active')
      expect(body_text(mail)).to include('Duration: Up to 1 hour')
    end

    it 'explains what happens next' do
      expect(mail.body.encoded).to include("don't need to do anything")
      expect(mail.body.encoded).to include('confirmation email')
      expect(mail.body.encoded).to include('troubleshooting help')
    end

    it 'includes DNS record reminders' do
      text = body_text(mail)
      expect(text).to include('CNAME record')
      expect(text).to include('A record')
      expect(text).to include('Name:')
      expect(text).to include('Type: CNAME')
      expect(text).to include('Type: A')
      expect(text).to include('216.24.57.1')
      expect(text).to match(/localhost|[a-z0-9\-]+\.bizblasts\.com/)
    end
  end

  describe 'default configuration' do
    it 'uses correct default from address' do
      mail = described_class.setup_instructions(business, user)
      expect(mail.from).to eq([ENV['MAILER_EMAIL']])
    end

    it 'falls back to default support email when ENV not set' do
      ENV.delete('SUPPORT_EMAIL')
      mail = described_class.setup_instructions(business, user)
      expect(mail.from).to eq([ENV['MAILER_EMAIL']])
    end

    it 'uses custom support email from ENV' do
      ENV['SUPPORT_EMAIL'] = 'custom@example.com'
      mail = described_class.setup_instructions(business, user)
      expect(mail.from).to eq([ENV['MAILER_EMAIL']])
      ENV.delete('SUPPORT_EMAIL')
    end
  end

  describe 'template rendering' do
    it 'renders HTML templates without errors' do
      %w[setup_instructions activation_success timeout_help monitoring_restarted].each do |template|
        mail = described_class.send(template, business, user)
        
        expect { mail.body.encoded }.not_to raise_error
        expect(mail.body.encoded).to be_present
        expect(mail.body.encoded.length).to be > 100  # Ensure substantial content
      end
    end

    it 'includes proper HTML structure' do
      mail = described_class.setup_instructions(business, user)
      
      expect(mail.body.encoded).to include('<!DOCTYPE html>')
      expect(mail.body.encoded).to include('<html>')
      expect(mail.body.encoded).to include('<head>')
      expect(mail.body.encoded).to include('<body>')
    end

    it 'includes responsive styling' do
      mail = described_class.setup_instructions(business, user)
      
      expect(mail.body.encoded).to include('viewport')
      expect(mail.body.encoded).to include('max-width')
      expect(mail.body.encoded).to include('font-family')
    end
  end
end