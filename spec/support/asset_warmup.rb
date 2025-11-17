# Asset Warmup for CI
#
# In CI environments, assets are pre-built during the CI pipeline.
# This warmup initializes the Rails asset pipeline and caches manifests
# without the overhead of starting a browser session.
#
RSpec.configure do |config|
  config.before(:suite) do
    next unless ENV['CI'] == 'true'

    begin
      # Initialize Rails asset pipeline
      # This ensures the asset manifest is loaded and cached before tests run
      if defined?(Rails) && Rails.application
        # Force load the asset manifest
        if Rails.application.config.respond_to?(:assets)
          # Touch the assets to ensure they're in the manifest
          Rails.application.assets_manifest&.assets
        end

        # Initialize ActionView assets if available
        if defined?(ActionView::Base)
          ActionView::Base.assets_manifest if ActionView::Base.respond_to?(:assets_manifest)
        end

        Rails.logger.info "[Asset Warmup] Asset pipeline initialized for CI - no browser session needed"
      end
    rescue => e
      # Log warning but don't fail - assets may still work
      warn "[Asset Warmup] Warning during initialization: #{e.class} - #{e.message}"
    end
  end
end

