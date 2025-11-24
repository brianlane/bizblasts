# frozen_string_literal: true

class CalendarSyncDiagnostics
  def self.run_diagnostics(business = nil)
    puts "🔍 Calendar Sync Diagnostics"
    puts "=" * 50
    
    if business
      puts "Business: #{business.name}"
      run_business_diagnostics(business)
    else
      run_global_diagnostics
    end
  end
  
  def self.run_business_diagnostics(business)
    puts "\n📊 Business Overview:"
    puts "- Staff members: #{business.staff_members.active.count}"
    puts "- Calendar connections: #{business.calendar_connections.active.count}"
    puts "- Recent bookings (30 days): #{business.bookings.where(created_at: 30.days.ago..).count}"
    
    puts "\n🔗 Calendar Connections:"
    business.calendar_connections.active.includes(:staff_member).each do |connection|
      puts "- #{connection.staff_member.name} (#{connection.provider_display_name})"
      puts "  Last synced: #{connection.last_synced_at || 'Never'}"
      puts "  Token expires: #{connection.token_expires_at || 'No expiration'}"
      puts "  Has access token: #{connection.access_token.present? ? 'Yes' : 'No'}"
      puts "  Has refresh token: #{connection.refresh_token.present? ? 'Yes' : 'No'}"
      puts "  Scopes: #{connection.scopes || 'None'}"
      puts "  Active: #{connection.active? ? 'Yes' : 'No'}"
      puts
    end
    
    puts "\n📅 Booking Sync Status:"
    business.staff_members.active.each do |staff|
      next unless staff.has_calendar_integrations?
      
      puts "#{staff.name}:"
      puts "  - Synced bookings: #{staff.synced_bookings_count}"
      puts "  - Pending sync: #{staff.pending_sync_bookings_count}"
      puts "  - Failed sync: #{staff.failed_sync_bookings_count}"
      puts "  - Success rate: #{staff.calendar_sync_success_rate}%"
      
      # Check recent booking sync attempts
      recent_bookings = staff.bookings.where(created_at: 7.days.ago..).order(created_at: :desc).limit(5)
      if recent_bookings.any?
        puts "  Recent bookings:"
        recent_bookings.each do |booking|
          puts "    - #{booking.start_time&.strftime('%m/%d %H:%M')}: #{booking.calendar_event_status.humanize}"
        end
      end
      puts
    end
    
    puts "\n📋 Recent Sync Logs:"
    recent_logs = CalendarSyncLog.joins(calendar_event_mapping: { booking: :business })
                                 .where(businesses: { id: business.id })
                                 .order(created_at: :desc)
                                 .limit(10)
                                 
    if recent_logs.any?
      recent_logs.each do |log|
        status_icon = log.successful_syncs? ? "✅" : "❌"
        puts "#{status_icon} #{log.created_at.strftime('%m/%d %H:%M')} - #{log.action_description}: #{log.outcome_description}"
        puts "   #{log.message}" if log.message.present?
      end
    else
      puts "No recent sync logs found"
    end
    
    puts "\n🔧 Environment Check:"
    check_environment_variables
    
    puts "\n⚙️  Background Jobs:"
    check_background_jobs
    
    puts "\n🚨 Common Issues:"
    check_common_issues(business)
  end
  
  def self.run_global_diagnostics
    puts "\n🌍 Global Overview:"
    puts "- Total businesses: #{Business.count}"
    puts "- Active calendar connections: #{CalendarConnection.active.count}"
    puts "- Total bookings needing sync: #{Booking.where(calendar_event_status: [:sync_pending, :not_synced]).count}"
    puts "- Failed sync bookings: #{Booking.where(calendar_event_status: :sync_failed).count}"
    
    check_environment_variables
    check_background_jobs
  end
  
  private
  
  def self.check_environment_variables
    # Check Google OAuth credentials (unified for Calendar and Business Profile)
    google_configured = GoogleOauthCredentials.configured?
    env_suffix = GoogleOauthCredentials.environment_suffix
    
    puts "Google OAuth API#{env_suffix}:"
    puts "  - Client ID: #{GoogleOauthCredentials.client_id.present? ? '✅ Set' : '❌ Missing'}"
    puts "  - Client Secret: #{GoogleOauthCredentials.client_secret.present? ? '✅ Set' : '❌ Missing'}"
    puts "  - Overall status: #{google_configured ? '✅ Configured' : '❌ Not configured'}"
    
    microsoft_client_id = ENV['MICROSOFT_CALENDAR_CLIENT_ID'].present?
    microsoft_client_secret = ENV['MICROSOFT_CALENDAR_CLIENT_SECRET'].present?
    
    puts "Microsoft Calendar API:"
    puts "  - Client ID: #{microsoft_client_id ? '✅ Set' : '❌ Missing'}"
    puts "  - Client Secret: #{microsoft_client_secret ? '✅ Set' : '❌ Missing'}"
  end
  
  def self.check_background_jobs
    # Check if solid_queue is running
    if defined?(SolidQueue)
      puts "Background job system: SolidQueue"
      # Could check for active workers/processes here
    else
      puts "Background job system: Unknown"
    end
    
    # Check recent job executions
    pending_jobs = 0
    failed_jobs = 0
    
    # This would depend on your job backend
    puts "Job status: Unable to check (requires job backend inspection)"
  end
  
  def self.check_common_issues(business)
    issues = []
    
    # Check for expired tokens
    expired_connections = business.calendar_connections.active.select(&:token_expired?)
    if expired_connections.any?
      issues << "#{expired_connections.count} calendar connection(s) have expired tokens"
    end
    
    # Check for connections without proper scopes
    insufficient_scope_connections = business.calendar_connections.active.reject(&:has_calendar_permissions?)
    if insufficient_scope_connections.any?
      issues << "#{insufficient_scope_connections.count} connection(s) missing calendar permissions"
    end
    
    # Check for bookings that should be synced but aren't
    staff_with_connections = business.staff_members.joins(:calendar_connections).where(calendar_connections: { active: true })
    unsynced_bookings = Booking.joins(:staff_member)
                              .where(staff_members: { id: staff_with_connections.ids })
                              .where(calendar_event_status: :not_synced)
                              .where(created_at: 7.days.ago..)
                              .count
    
    if unsynced_bookings > 0
      issues << "#{unsynced_bookings} recent booking(s) not synced despite having calendar connections"
    end
    
    if issues.any?
      issues.each { |issue| puts "⚠️  #{issue}" }
    else
      puts "✅ No obvious issues detected"
    end
  end
end