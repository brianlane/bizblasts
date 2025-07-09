require 'rails_helper'

RSpec.describe Public::BaseController, type: :controller do
  describe '#no_store!' do
    it 'sets the appropriate Cache-Control headers on the response' do
      # Prepare a fresh response object
      test_response = ActionDispatch::TestResponse.new
      # Stub the controller's response to use our test response
      allow(controller).to receive(:response).and_return(test_response)

      # Invoke the private helper method
      controller.send(:no_store!)

      # Verify headers set correctly
      expect(test_response.headers['Cache-Control']).to eq('no-store, no-cache, must-revalidate, max-age=0')
      expect(test_response.headers['Pragma']).to eq('no-cache')
      expect(test_response.headers['Expires']).to eq('0')
    end
  end
end 