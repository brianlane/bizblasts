require 'rails_helper'

RSpec.describe Users::SessionsController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  describe '#sanitize_return_to' do
    let(:controller) { Users::SessionsController.new }
    
    context 'valid paths' do
      it 'allows simple absolute paths' do
        expect(controller.send(:sanitize_return_to, '/dashboard')).to eq('/dashboard')
      end
      
      it 'allows paths with query parameters' do
        expect(controller.send(:sanitize_return_to, '/search?q=test')).to eq('/search?q=test')
      end
      
      it 'allows paths with fragments' do
        expect(controller.send(:sanitize_return_to, '/page#section')).to eq('/page#section')
      end
    end
    
    context 'security rejections' do
      it 'rejects protocol-relative URLs' do
        expect(controller.send(:sanitize_return_to, '//evil.com/path')).to be_nil
      end
      
      it 'rejects javascript: scheme' do
        expect(controller.send(:sanitize_return_to, '/javascript:alert(1)')).to be_nil
      end
      
      it 'rejects data: scheme' do
        expect(controller.send(:sanitize_return_to, '/data:text/html,<script>alert(1)</script>')).to be_nil
      end
      
      it 'rejects CR/LF injection attempts' do
        expect(controller.send(:sanitize_return_to, "/path\r\nLocation: http://evil.com")).to be_nil
        expect(controller.send(:sanitize_return_to, "/path\nLocation: http://evil.com")).to be_nil
        expect(controller.send(:sanitize_return_to, "/path%0d%0aLocation: http://evil.com")).to be_nil
      end
      
      it 'rejects paths not starting with /' do
        expect(controller.send(:sanitize_return_to, 'relative/path')).to be_nil
        expect(controller.send(:sanitize_return_to, 'http://example.com')).to be_nil
      end
      
      it 'rejects overly long paths' do
        long_path = '/' + 'a' * 2001
        expect(controller.send(:sanitize_return_to, long_path)).to be_nil
      end
      
      it 'strips dangerous characters' do
        result = controller.send(:sanitize_return_to, '/path<script>"test"</script>')
        expect(result).to eq('/pathscripttest/script')
      end
      
      it 'rejects nil and empty strings' do
        expect(controller.send(:sanitize_return_to, nil)).to be_nil
        expect(controller.send(:sanitize_return_to, '')).to be_nil
        expect(controller.send(:sanitize_return_to, '   ')).to be_nil
      end
    end
    
    context 'edge cases' do
      it 'handles unicode characters safely' do
        result = controller.send(:sanitize_return_to, '/café')
        expect(result).to eq('/café')
      end
      
      it 'handles encoded characters' do
        result = controller.send(:sanitize_return_to, '/path%20with%20spaces')
        expect(result).to eq('/path%20with%20spaces')
      end
    end
  end

  describe 'session-based return_to handling' do
    controller(Users::SessionsController) do
    end

    it 'uses session-stored return_to after sign in and clears it' do
      user = create(:user)
      session[:return_to] = '/dashboard'
      allow(subject).to receive(:after_sign_in_path_for).and_call_original
      path = subject.send(:after_sign_in_path_for, user)
      expect(path).to eq('/dashboard')
      expect(session[:return_to]).to be_nil
    end

    it 'ignores unsafe session return_to and falls back' do
      user = create(:user)
      session[:return_to] = "//evil.com/path"
      allow(subject).to receive(:stored_location_for).and_return(nil)
      path = subject.send(:after_sign_in_path_for, user)
      # Default factory user is a client; controller falls back to dashboard for clients
      expect(path).to eq('/dashboard')
      expect(session[:return_to]).to be_nil
    end
  end
end
