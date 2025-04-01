# frozen_string_literal: true

# Configure SolidCache
if defined?(SolidCache)
  Rails.application.config.to_prepare do
    SolidCache.configuration do |config|
      config.store = if Rails.env.local?
                       # Use memory store in development for simplicity
                       :memory_store
                     else
                       # Use PostgreSQL store in production
                       :solid_store
                     end
    end
  end
end

# Configure Rails cache store
Rails.application.config.cache_store = :solid_cache_store
