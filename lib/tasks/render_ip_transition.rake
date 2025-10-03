# frozen_string_literal: true

namespace :render do
  desc "Check connectivity to all external APIs for IP transition monitoring"
  task check_external_apis: :environment do
    puts "🔍 Checking External API Connectivity..."
    puts "=" * 60

    results = {}
    total_checks = 0
    passed_checks = 0

    # Check Stripe API
    print "Stripe API................... "
    begin
      if StripeService.stripe_configured?
        StripeService.configure_stripe_api_key
        Stripe::Account.list(limit: 1)
        puts "✅ PASS"
        results[:stripe] = { status: :pass, error: nil }
        passed_checks += 1
      else
        puts "⚠️  SKIP (not configured)"
        results[:stripe] = { status: :skip, error: "Not configured" }
      end
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:stripe] = { status: :fail, error: e.message }
    end
    total_checks += 1

    # Check Twilio API
    print "Twilio API................... "
    begin
      if defined?(TWILIO_ACCOUNT_SID) && TWILIO_ACCOUNT_SID != 'MISSING_TWILIO_ACCOUNT_SID'
        client = Twilio::REST::Client.new(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        client.api.accounts(TWILIO_ACCOUNT_SID).fetch
        puts "✅ PASS"
        results[:twilio] = { status: :pass, error: nil }
        passed_checks += 1
      else
        puts "⚠️  SKIP (not configured)"
        results[:twilio] = { status: :skip, error: "Not configured" }
      end
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:twilio] = { status: :fail, error: e.message }
    end
    total_checks += 1

    # Check Resend API
    print "Resend API................... "
    begin
      if ENV['RESEND_API_KEY'].present?
        require 'net/http'
        uri = URI('https://api.resend.com/domains')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{ENV['RESEND_API_KEY']}"
        request['Content-Type'] = 'application/json'

        response = http.request(request)
        if response.code.to_i < 400
          puts "✅ PASS"
          results[:resend] = { status: :pass, error: nil }
          passed_checks += 1
        else
          puts "❌ FAIL - HTTP #{response.code}"
          results[:resend] = { status: :fail, error: "HTTP #{response.code}" }
        end
      else
        puts "⚠️  SKIP (not configured)"
        results[:resend] = { status: :skip, error: "Not configured" }
      end
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:resend] = { status: :fail, error: e.message }
    end
    total_checks += 1

    # Check AWS S3
    print "AWS S3....................... "
    begin
      if ENV['IAM_AWS_ACCESS_KEY'].present? && ENV['AWS_BUCKET'].present?
        require 'aws-sdk-s3'
        s3_client = Aws::S3::Client.new(
          access_key_id: ENV['IAM_AWS_ACCESS_KEY'],
          secret_access_key: ENV['IAM_AWS_SECRET_ACCESS_KEY'],
          region: ENV['AWS_REGION']
        )
        s3_client.head_bucket(bucket: ENV['AWS_BUCKET'])
        puts "✅ PASS"
        results[:aws_s3] = { status: :pass, error: nil }
        passed_checks += 1
      else
        puts "⚠️  SKIP (not configured)"
        results[:aws_s3] = { status: :skip, error: "Not configured" }
      end
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:aws_s3] = { status: :fail, error: e.message }
    end
    total_checks += 1

    # Check Google Places API
    print "Google Places API............ "
    begin
      if ENV['GOOGLE_PLACES_API_KEY'].present?
        require 'net/http'
        uri = URI('https://places.googleapis.com/v1/places:searchText')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-Goog-Api-Key'] = ENV['GOOGLE_PLACES_API_KEY']
        request['X-Goog-FieldMask'] = 'places.id'
        request.body = { textQuery: 'test' }.to_json

        response = http.request(request)
        if response.code.to_i < 400
          puts "✅ PASS"
          results[:google_places] = { status: :pass, error: nil }
          passed_checks += 1
        else
          puts "❌ FAIL - HTTP #{response.code}"
          results[:google_places] = { status: :fail, error: "HTTP #{response.code}" }
        end
      else
        puts "⚠️  SKIP (not configured)"
        results[:google_places] = { status: :skip, error: "Not configured" }
      end
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:google_places] = { status: :fail, error: e.message }
    end
    total_checks += 1

    # Check Render API
    print "Render API................... "
    begin
      if ENV['RENDER_API_KEY'].present? && ENV['RENDER_SERVICE_ID'].present?
        render_service = RenderDomainService.new
        # Try to list domains as a connectivity test
        domains = render_service.list_domains
        puts "✅ PASS"
        results[:render_api] = { status: :pass, error: nil }
        passed_checks += 1
      else
        puts "⚠️  SKIP (not configured)"
        results[:render_api] = { status: :skip, error: "Not configured" }
      end
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:render_api] = { status: :fail, error: e.message }
    end
    total_checks += 1

    # Check Domain Health (sample check)
    print "Domain Health Check.......... "
    begin
      checker = DomainHealthChecker.new('example.com')
      result = checker.check_health
      puts "✅ PASS"
      results[:domain_health] = { status: :pass, error: nil }
      passed_checks += 1
    rescue => e
      puts "❌ FAIL - #{e.message}"
      results[:domain_health] = { status: :fail, error: e.message }
    end
    total_checks += 1

    puts "=" * 60
    puts "📊 Summary: #{passed_checks}/#{total_checks} checks passed"

    # Log results for monitoring
    Rails.logger.info "[ExternalAPICheck] Connectivity check completed: #{passed_checks}/#{total_checks} passed"
    results.each do |service, result|
      if result[:status] == :fail
        Rails.logger.error "[ExternalAPICheck] #{service.to_s.upcase} FAILED: #{result[:error]}"
      end
    end

    # Exit with error code if any critical services failed
    critical_services = [:stripe, :twilio, :resend]
    failed_critical = results.select { |service, result|
      critical_services.include?(service) && result[:status] == :fail
    }

    if failed_critical.any?
      puts "❌ CRITICAL: #{failed_critical.keys.join(', ')} failed - this may impact core functionality"
      exit 1
    elsif passed_checks < total_checks
      puts "⚠️  WARNING: Some non-critical services failed"
      exit 2
    else
      puts "✅ ALL SYSTEMS OPERATIONAL"
      exit 0
    end
  end

  desc "Monitor external API failures (for cron job)"
  task monitor_api_failures: :environment do
    # This task is designed to be run periodically via cron
    # It will only output if there are failures, making it suitable for monitoring

    results = {}
    failed_services = []

    # Test critical services silently
    critical_services = {
      stripe: -> {
        return false unless StripeService.stripe_configured?
        StripeService.configure_stripe_api_key
        Stripe::Account.list(limit: 1)
        true
      },
      twilio: -> {
        return false unless defined?(TWILIO_ACCOUNT_SID) && TWILIO_ACCOUNT_SID != 'MISSING_TWILIO_ACCOUNT_SID'
        client = Twilio::REST::Client.new(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        client.api.accounts(TWILIO_ACCOUNT_SID).fetch
        true
      },
      resend: -> {
        return false unless ENV['RESEND_API_KEY'].present?
        require 'net/http'
        uri = URI('https://api.resend.com/domains')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 5
        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{ENV['RESEND_API_KEY']}"
        response = http.request(request)
        response.code.to_i < 400
      }
    }

    critical_services.each do |service_name, check_proc|
      begin
        unless check_proc.call
          failed_services << service_name
        end
      rescue => e
        failed_services << service_name
        Rails.logger.error "[APIMonitoring] #{service_name.to_s.upcase} check failed: #{e.message}"
      end
    end

    if failed_services.any?
      puts "🚨 ALERT: External API failures detected: #{failed_services.join(', ')}"
      puts "This may be related to the Render IP address transition."
      puts "Check external service IP allowlists and verify new Render IPs are configured."
      Rails.logger.error "[APIMonitoring] CRITICAL: Failed services: #{failed_services.join(', ')}"
      exit 1
    end

    # Silent success for cron jobs
    exit 0
  end

  desc "Test all webhook endpoints are accessible"
  task test_webhooks: :environment do
    puts "🔍 Testing Webhook Endpoint Accessibility..."
    puts "=" * 60

    webhook_endpoints = [
      { name: "Stripe Webhooks", path: "/webhooks/stripe", method: "POST" },
      { name: "Twilio Delivery", path: "/webhooks/twilio", method: "POST" },
      { name: "Twilio Inbound", path: "/webhooks/twilio/inbound", method: "POST" }
    ]

    webhook_endpoints.each do |endpoint|
      print "#{endpoint[:name]}".ljust(25) + "... "

      begin
        # Make a test request to verify the endpoint exists and is routable
        # We expect authentication errors, not routing errors
        require 'net/http'

        # Use the application's configured domain
        host = Rails.env.production? ? ENV['RAILS_HOST'] || 'bizblasts.onrender.com' : 'localhost'
        port = Rails.env.production? ? 443 : (ENV['PORT'] || 3000)

        uri = URI("#{Rails.env.production? ? 'https' : 'http'}://#{host}:#{port}#{endpoint[:path]}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = Rails.env.production?
        http.read_timeout = 10

        request = case endpoint[:method]
        when "POST"
          Net::HTTP::Post.new(uri.path)
        else
          Net::HTTP::Get.new(uri.path)
        end

        response = http.request(request)

        # We expect 401/403 (auth errors) or 422 (validation errors), not 404 (routing errors)
        if [401, 403, 422].include?(response.code.to_i)
          puts "✅ ACCESSIBLE (#{response.code})"
        elsif response.code.to_i == 404
          puts "❌ NOT FOUND (404)"
        else
          puts "⚠️  UNEXPECTED (#{response.code})"
        end

      rescue => e
        puts "❌ ERROR - #{e.message}"
      end
    end

    puts "=" * 60
    puts "Note: Webhook endpoints should return 401/403/422 (auth/validation errors),"
    puts "      not 404 (routing errors). This confirms they are accessible."
  end
end