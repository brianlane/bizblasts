# frozen_string_literal: true

namespace :calendar do
  desc "Run calendar sync diagnostics for a business or globally"
  task :diagnostics, [:business_id] => :environment do |t, args|
    require_relative '../calendar_sync_diagnostics'
    
    if args[:business_id]
      business = Business.find(args[:business_id])
      CalendarSyncDiagnostics.run_diagnostics(business)
    else
      CalendarSyncDiagnostics.run_diagnostics
    end
  end
  
  desc "Force sync all pending bookings for a business"
  task :force_sync, [:business_id] => :environment do |t, args|
    business = Business.find(args[:business_id])
    
    puts "🔄 Force syncing all pending bookings for #{business.name}"
    
    pending_bookings = business.bookings
                              .joins(:staff_member)
                              .joins('LEFT JOIN calendar_connections ON calendar_connections.staff_member_id = staff_members.id')
                              .where(calendar_connections: { active: true })
                              .where(calendar_event_status: [:not_synced, :sync_pending])
    
    puts "Found #{pending_bookings.count} bookings to sync"
    
    pending_bookings.find_each do |booking|
      puts "Syncing booking #{booking.id} (#{booking.service_name} - #{booking.start_time})"
      Calendar::SyncBookingJob.perform_later(booking.id)
    end
    
    puts "✅ Sync jobs enqueued"
  end
  
  desc "Check calendar connection health"
  task :health_check, [:business_id] => :environment do |t, args|
    business = Business.find(args[:business_id])
    
    puts "🏥 Calendar Connection Health Check for #{business.name}"
    puts "=" * 60
    
    business.calendar_connections.active.each do |connection|
      puts "\n#{connection.staff_member.name} - #{connection.provider_display_name}:"
      
      # Test connection
      begin
        service = case connection.provider
                 when 'google'
                   Calendar::GoogleService.new(connection)
                 else
                   puts "  ❓ Unsupported provider"
                   next
                 end
        
        # Try a simple test
        result = service.import_events(Date.current, Date.current + 1.day)
        
        if result && result[:success]
          puts "  ✅ Connection healthy"
        else
          puts "  ❌ Connection failed: #{service.errors.full_messages.join(', ')}"
        end
      rescue => e
        puts "  💥 Error: #{e.message}"
      end
    end
  end
  
  desc "Refresh expired calendar tokens"
  task :refresh_tokens, [:business_id] => :environment do |t, args|
    business = Business.find(args[:business_id])
    
    puts "🔄 Refreshing expired tokens for #{business.name}"
    
    expired_connections = business.calendar_connections.active.select(&:needs_refresh?)
    
    if expired_connections.empty?
      puts "✅ No expired tokens found"
      return
    end
    
    expired_connections.each do |connection|
      puts "Refreshing token for #{connection.staff_member.name}"
      
      oauth_handler = Calendar::OauthHandler.new
      result = oauth_handler.refresh_token(connection)
      
      if result
        puts "  ✅ Token refreshed successfully"
      else
        puts "  ❌ Failed to refresh token: #{oauth_handler.errors.full_messages.join(', ')}"
      end
    end
  end
end