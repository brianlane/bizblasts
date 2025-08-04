# frozen_string_literal: true

class BusinessManager::Settings::CalendarIntegrationsController < BusinessManager::BaseController
  before_action :set_calendar_connection, only: [:show, :destroy, :toggle_default, :resync]
  
  def index
    @staff_members = current_business.staff_members.active.includes(:calendar_connections, :user)
    @calendar_connections = current_business.calendar_connections.includes(:staff_member).active
    @sync_statistics = calculate_sync_statistics
    @providers = available_providers
  end
  
  def show
    @sync_logs = CalendarSyncLog.joins(:calendar_event_mapping)
                                .where(calendar_event_mappings: { calendar_connection_id: @calendar_connection.id })
                                .includes(calendar_event_mapping: [:booking, :calendar_connection])
                                .order(created_at: :desc)
                                .limit(20)
  end
  
  def connect
    provider = params[:provider]
    staff_member_id = params[:staff_member_id]
    
    unless available_providers.include?(provider)
      redirect_to business_manager_settings_calendar_integrations_path,
                  alert: "Unsupported calendar provider: #{provider}"
      return
    end
    
    staff_member = current_business.staff_members.find(staff_member_id)
    
    # Check if connection already exists
    existing_connection = staff_member.calendar_connections
                                    .where(provider: provider)
                                    .active
                                    .first
    
    if existing_connection
      redirect_to business_manager_settings_calendar_integrations_path,
                  alert: "#{provider.humanize} Calendar is already connected for #{staff_member.name}"
      return
    end
    
    if provider == 'caldav'
      # CalDAV uses manual setup, redirect to setup form
      redirect_to new_caldav_business_manager_settings_calendar_integrations_path(staff_member_id: staff_member_id)
    else
      # OAuth providers (Google, Microsoft)
      oauth_handler = Calendar::OauthHandler.new
      scheme = request.ssl? ? 'https' : 'http'
      host = Rails.application.config.main_domain
      # Append port only if main_domain does NOT already include one
      port_str = if host.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                   ''
                 else
                   ":#{request.port}"
                 end
      redirect_uri = "#{scheme}://#{host}#{port_str}/oauth/calendar/#{provider}/callback"
      
      auth_url = oauth_handler.authorization_url(
        provider,
        current_business.id,
        staff_member.id,
        redirect_uri
      )
      
      if auth_url
        redirect_to auth_url, allow_other_host: true
      else
        error_message = oauth_handler.errors.full_messages.join(', ')
        redirect_to business_manager_settings_calendar_integrations_path,
                    alert: "Failed to initiate calendar connection: #{error_message}"
      end
    end
  end
  
  def new_caldav
    @staff_member = current_business.staff_members.find(params[:staff_member_id])
    @caldav_providers = Calendar::CaldavFactory.available_providers
    @calendar_connection = CalendarConnection.new(
      business: current_business,
      staff_member: @staff_member,
      provider: :caldav
    )
  end
  
  def create_caldav
    staff_member_id = params[:staff_member_id] || caldav_connection_params[:staff_member_id]
    @staff_member = current_business.staff_members.find(staff_member_id)
    @caldav_providers = Calendar::CaldavFactory.available_providers
    
    connection_params = caldav_connection_params.except(:staff_member_id)
    connection_params[:business] = current_business
    connection_params[:staff_member] = @staff_member
    connection_params[:provider] = :caldav
    
    @calendar_connection = CalendarConnection.new(connection_params)
    
    if @calendar_connection.valid?
      # Test the connection before saving
      test_result = Calendar::CaldavFactory.test_connection(
        @calendar_connection.caldav_username,
        @calendar_connection.caldav_password,
        @calendar_connection.caldav_url,
        @calendar_connection.caldav_provider
      )
      
      if test_result[:success]
        @calendar_connection.active = true
        if @calendar_connection.save
          redirect_to business_manager_settings_calendar_integrations_path,
                      notice: "Successfully connected #{@calendar_connection.provider_display_name} for #{@staff_member.name}"
        else
          render :new_caldav
        end
      else
        @calendar_connection.errors.add(:base, test_result[:message])
        render :new_caldav
      end
    else
      render :new_caldav
    end
  end
  
  def test_caldav
    result = Calendar::CaldavFactory.test_connection(
      params[:username],
      params[:password],
      params[:url],
      params[:provider_type]
    )
    
    render json: result
  end

  def destroy
    provider_name = @calendar_connection.provider_display_name
    staff_name = @calendar_connection.staff_member.name
    
    # Remove default calendar connection reference first
    staff_member = @calendar_connection.staff_member
    if staff_member.default_calendar_connection == @calendar_connection
      staff_member.update(default_calendar_connection: nil)
    end
    
    @calendar_connection.destroy
    
    redirect_to business_manager_settings_calendar_integrations_path,
                notice: "#{provider_name} calendar connection removed for #{staff_name}"
  end
  
  def toggle_default
    staff_member = @calendar_connection.staff_member
    
    if staff_member.default_calendar_connection == @calendar_connection
      staff_member.update(default_calendar_connection: nil)
      message = "Removed default calendar setting"
    else
      staff_member.update(default_calendar_connection: @calendar_connection)
      message = "Set as default calendar for #{staff_member.name}"
    end
    
    redirect_to business_manager_settings_calendar_integrations_path, notice: message
  end
  
  def resync
    # Enqueue background job to resync this connection's events
    Calendar::ImportAvailabilityJob.perform_later(@calendar_connection.staff_member.id)
    
    # Also sync any pending bookings for this staff member
    pending_bookings = @calendar_connection.staff_member.bookings
                                         .where(calendar_event_status: [:not_synced, :sync_pending])
                                         .limit(10)
    
    pending_bookings.each do |booking|
      Calendar::SyncBookingJob.perform_later(booking.id)
    end
    
    redirect_to business_manager_settings_calendar_integrations_path,
                notice: "Calendar resync initiated for #{@calendar_connection.staff_member.name}"
  end
  
  def batch_sync
    # Trigger batch sync for all active calendar connections
    Calendar::BatchSyncJob.perform_later(current_business.id, { 'action' => 'sync_pending' })
    
    redirect_to business_manager_settings_calendar_integrations_path,
                notice: "Batch calendar sync initiated for all staff members"
  end
  
  def import_availability
    # Import availability for all staff with calendar connections
    Calendar::BatchSyncJob.perform_later(current_business.id, { 'action' => 'import_all_availability' })
    
    redirect_to business_manager_settings_calendar_integrations_path,
                notice: "Availability import initiated for all connected calendars"
  end
  
  def oauth_callback
    # This should not be called as OAuth callbacks go to the main domain
    # But included for completeness
    redirect_to business_manager_settings_calendar_integrations_path,
                alert: "Invalid OAuth callback"
  end
  
  private
  
  def set_calendar_connection
    @calendar_connection = current_business.calendar_connections.find(params[:id])
  end
  
  def available_providers
    providers = []
    
    # Check if Google Calendar credentials are configured
    google_configured = if Rails.env.development? || Rails.env.test?
                          ENV['GOOGLE_CALENDAR_CLIENT_ID_DEV'].present? && ENV['GOOGLE_CALENDAR_CLIENT_SECRET_DEV'].present?
                        else
                          ENV['GOOGLE_CALENDAR_CLIENT_ID'].present? && ENV['GOOGLE_CALENDAR_CLIENT_SECRET'].present?
                        end
    
    providers << 'google' if google_configured
    
    # Check if Microsoft Graph credentials are configured
    if ENV['MICROSOFT_CALENDAR_CLIENT_ID'].present? && ENV['MICROSOFT_CALENDAR_CLIENT_SECRET'].present?
      providers << 'microsoft'
    end
    
    # CalDAV is always available (no external credentials needed)
    providers << 'caldav'
    
    providers
  end
  
  def caldav_connection_params
    params.require(:calendar_connection).permit(:staff_member_id, :caldav_username, :caldav_password, :caldav_url, :caldav_provider)
  end

  def calculate_sync_statistics
    return {} if current_business.calendar_connections.empty?
    
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.sync_statistics(current_business, 24.hours.ago)
  end
  
  def calendar_connection_params
    params.require(:calendar_connection).permit(:provider, :staff_member_id)
  end
end