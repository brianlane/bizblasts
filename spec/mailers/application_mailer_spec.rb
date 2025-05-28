# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationMailer, type: :mailer do
  # This is a base class, so we'll just test the basic configuration
  it 'uses the correct default from address' do
    expect(ApplicationMailer.default[:from]).to eq(ENV['MAILER_EMAIL'] || 'from@example.com')
  end
  
  it 'uses the correct layout' do
    expect(ApplicationMailer._layout).to eq('mailer')
  end
end 