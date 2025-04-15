require 'rails_helper'

RSpec.describe "Business User Session Management", type: :request do
  let!(:business) { create(:business, hostname: 'testbiz', host_type: 'subdomain') }
  let!(:user) { create(:user, role: :manager, business: business, password: 'password') }

  let(:main_domain_host) { "lvh.me" }
  let(:subdomain_host) { "#{business.hostname}.#{main_domain_host}" }

  it "allows user to log in on main domain and access dashboard on subdomain" do
    # --- Step 1: Log in on the main domain --- 
    login_params = {
      user: {
        email: user.email,
        password: 'password'
      }
    }

    post user_session_path, params: login_params, headers: { "Host" => main_domain_host }

    # Assert successful login redirect
    expect(response).to have_http_status(:see_other) # 303
    # Assert redirection is towards the subdomain dashboard
    expect(response.location).to include("//#{subdomain_host}")
    expect(response.location).to include("/dashboard")

    # Extract the session cookie directly from the Set-Cookie header
    set_cookie_header = response.headers['Set-Cookie']
    expect(set_cookie_header).not_to be_nil, "Set-Cookie header was missing in the response"
    # Simple parsing, might need refinement if multiple cookies are set
    session_cookie_value = set_cookie_header.match(/_bizblasts_session_test=([^;]+);/)[1]
    expect(session_cookie_value).not_to be_nil, "Session cookie value not found in Set-Cookie header"

    # --- Step 2: Access dashboard on subdomain using the session cookie --- 
    
    # Follow the redirect manually, sending the cookie and correct host header
    get response.location, headers: { 
      "Host" => subdomain_host,
      "Cookie" => "_bizblasts_session_test=#{session_cookie_value}"
    }
    
    # Assert successful access to the dashboard
    expect(response).to have_http_status(:ok) # Should be 200 OK, not 401 or 302
    
    # Assert dashboard content is present
    expect(response.body).to include("Dashboard") # Check for specific dashboard content
    expect(response.body).to include(user.email)   # Check if user info is present
  end
end 