# Allow lvh.me and subdomains for development and testing
# Used for subdomain testing with Capybara

if Rails.env.development? || Rails.env.test?
  # Allow lvh.me and all subdomains (*.lvh.me)
  Rails.application.config.hosts << "lvh.me"
  Rails.application.config.hosts << ".lvh.me"
  
  # Allow localhost and all ports/subdomains 
  Rails.application.config.hosts << "localhost"
  Rails.application.config.hosts << ".localhost"
  
  # For Capybara testing with specific port
  Rails.application.config.hosts << "lvh.me:9887"
  Rails.application.config.hosts << ".lvh.me:9887"
end 