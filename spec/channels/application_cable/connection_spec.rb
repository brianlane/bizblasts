# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) } 

  it "successfully connects with a verified user" do
    # Stub env['warden'] to simulate a logged-in user
    warden_double = double('Warden', user: user)
    allow_any_instance_of(ApplicationCable::Connection).to receive(:env).and_return({'warden' => warden_double})
    
    # Connect without needing specific headers now
    connect "/cable"

    # Assert the connection identifier is set
    expect(connection.current_user).to eq(user)
  end

  it "rejects connection without a verified user" do
    # Stub env['warden'] to simulate no logged-in user
    warden_double = double('Warden', user: nil)
    allow_any_instance_of(ApplicationCable::Connection).to receive(:env).and_return({'warden' => warden_double})
    
    # Expect the connection to be rejected
    expect { connect "/cable" }.to have_rejected_connection
  end
end
