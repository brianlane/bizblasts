require 'rails_helper'

RSpec.describe "Application Routes", type: :request do
  before do
    # Stub all asset helpers to avoid pipeline issues
    allow_any_instance_of(ActionView::Base).to receive(:stylesheet_link_tag).and_return("<link rel='stylesheet' href='/dummy.css'>")
    allow_any_instance_of(ActionView::Base).to receive(:javascript_include_tag).and_return("<script src='/dummy.js'></script>")
    allow_any_instance_of(ActionView::Base).to receive(:asset_path).and_return("/assets/dummy.png")
    allow_any_instance_of(ActionView::Base).to receive(:asset_url).and_return("/assets/dummy.png")
  end

  describe "Public routes" do
    it "GET / returns success" do
      get "/"
      expect(response).to have_http_status(:success)
    end
  end

  describe "Authentication routes" do
    it "GET /users/sign_in returns success" do
      get new_user_session_path
      expect(response).to have_http_status(:success)
    end

    it "POST /users/sign_in returns success (redirect)" do
      # Assuming valid user credentials lead to redirect
      # This might need actual user creation and sign-in attempt depending on setup
      user = create(:user, email: 'test@example.com', password: 'password', password_confirmation: 'password') # Create the user
      post user_session_path, params: { user: { email: user.email, password: user.password } }
      # Expect redirect to root or dashboard, adjust as necessary
      # For simplicity, checking for redirect status
      # Updated to expect :see_other (303) for Turbo redirect
      expect(response).to have_http_status(:see_other)
    end

    it "GET /users/password/new returns success" do
      get new_user_password_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "Admin routes" do
    let(:admin_user) { create(:admin_user) }

    it "GET /admin/login returns success" do
      get "/admin/login"
      expect(response).to have_http_status(:success)
    end

    context "when authenticated" do
      before do
        sign_in admin_user
      end

      it "GET /admin returns success" do
        get "/admin"
        expect(response).to have_http_status(:success)
      end

      it "GET /admin/dashboard returns success" do
        get "/admin/dashboard"
        expect(response).to have_http_status(:success)
      end
    end
  end
end 