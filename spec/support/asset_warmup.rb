RSpec.configure do |config|
  config.before(:suite) do
    next unless ENV['CI'] == 'true'

    begin
      session = Capybara::Session.new(Capybara.javascript_driver, Capybara.app)

      %w[/assets/application.js /assets/application.css].each do |asset_path|
        session.visit(asset_path)
      end
    rescue => e
      warn "[Spec Asset Warmup] Failed to warm assets: #{e.class} - #{e.message}"
    ensure
      session&.driver&.quit
    end
  end
end

