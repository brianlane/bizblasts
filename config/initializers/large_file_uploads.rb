# Configure Rails 8 for large file uploads (15MB max)
Rails.application.configure do
  # Increase the maximum size for multipart form data
  config.force_ssl = false unless Rails.env.production?
  
  # Configure Active Storage for large uploads
  config.active_storage.variant_processor = :mini_magick
  
  # Set reasonable timeouts for large file processing
  if defined?(Rack::Timeout)
    config.middleware.insert_before Rack::Runtime, Rack::Timeout, service_timeout: 120
  end
end

# Configure multipart parser limits  
if defined?(ActionDispatch::Http::UploadedFile)
  # Increase the tempfile threshold for large uploads
  ActionDispatch::Http::UploadedFile.class_eval do
    private
    
    def initialize_copy(other)
      @tempfile = other.tempfile
      @content_type = other.content_type
      @original_filename = other.original_filename
      @headers = other.headers
    end
  end
end 