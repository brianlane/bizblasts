# Configure SolidCache
if defined?(SolidCache)
  Rails.application.config.to_prepare do
    SolidCache.configuration do |config|
      if Rails.env.development? || Rails.env.test?
        # Use memory store in development for simplicity
        config.store = :memory_store
      else
        # Use PostgreSQL store in production
        config.store = :solid_store
      end
    end
  end
end

# Configure Rails cache store
Rails.application.config.cache_store = :solid_cache_store 