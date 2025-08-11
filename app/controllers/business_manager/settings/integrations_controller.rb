# frozen_string_literal: true

module BusinessManager
  module Settings
    class IntegrationsController < BusinessManager::BaseController
      before_action :set_business
      before_action :authorize_business_settings

      # GET /manage/settings/integrations
      def index
        # Show integrations overview including Google Business Reviews and Calendar Integrations
        @staff_members = current_business.staff_members.active.includes(:calendar_connections, :user)
        @calendar_connections = current_business.calendar_connections.includes(:staff_member).active
        @sync_statistics = calculate_sync_statistics
        @providers = available_providers
      end

      # Google Business Search and Connection Actions
      
      # GET /manage/settings/integrations/google-business/search
      def google_business_search
        query = params[:query]&.strip
        location = params[:location]&.strip
        
        if query.blank?
          render json: { error: 'Search query is required' }, status: :bad_request
          return
        end
        
        # Use business address as location context if no location provided
        if location.blank? && @business.address.present?
          location = "#{@business.address}, #{@business.city}, #{@business.state}"
        end
        
        result = GooglePlacesSearchService.search_businesses(query, location)
        render json: result
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business search error: #{e.message}"
        render json: { error: 'Search failed' }, status: :internal_server_error
      end

      # GET /manage/settings/integrations/google-business/details/:place_id
      def google_business_details
        place_id = params[:place_id]
        
        if place_id.blank?
          render json: { error: 'Place ID is required' }, status: :bad_request
          return
        end
        
        result = GooglePlacesSearchService.get_business_details(place_id)
        render json: result
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business details error: #{e.message}"
        render json: { error: 'Failed to fetch business details' }, status: :internal_server_error
      end

      # POST /manage/settings/integrations/google-business/connect
      def google_business_connect
        place_id = params[:place_id]&.strip
        business_name = params[:business_name]&.strip
        
        if place_id.blank?
          render json: { error: 'Place ID is required' }, status: :bad_request
          return
        end
        
        # Verify the place_id is valid by fetching details
        details_result = GooglePlacesSearchService.get_business_details(place_id)
        
        if details_result[:error]
          render json: { error: details_result[:error] }, status: :bad_request
          return
        end
        
        # Update business with Google Place ID
        verification = GoogleBusinessVerificationService.verify_match(@business, details_result[:business])
        unless verification[:ok]
          render json: {
            error: 'Selected Google listing does not appear to belong to your business',
            details: verification[:errors]
          }, status: :forbidden
          return
        end

        if @business.update(google_place_id: place_id)
          # Log the connection for audit purposes
          Rails.logger.info "[GoogleBusiness] Connected business #{@business.id} to Google Place ID: #{place_id} (#{business_name})"
          
          render json: { 
            success: true, 
            message: 'Google Business successfully connected!',
            business: details_result[:business]
          }
        else
          render json: { 
            error: 'Failed to save Google Business connection', 
            details: @business.errors.full_messages 
          }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business connect error: #{e.message}"
        render json: { error: 'Connection failed' }, status: :internal_server_error
      end

      # DELETE /manage/settings/integrations/google-business/disconnect
      def google_business_disconnect
        old_place_id = @business.google_place_id
        
        if @business.update(google_place_id: nil)
          Rails.logger.info "[GoogleBusiness] Disconnected business #{@business.id} from Google Place ID: #{old_place_id}"
          
          render json: { 
            success: true, 
            message: 'Google Business successfully disconnected' 
          }
        else
          render json: { 
            error: 'Failed to disconnect Google Business', 
            details: @business.errors.full_messages 
          }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business disconnect error: #{e.message}"
        render json: { error: 'Disconnection failed' }, status: :internal_server_error
      end

      # GET /manage/settings/integrations/google-business/status
      def google_business_status
        if @business.google_place_id.present?
          # Fetch current business details to show in UI
          result = GooglePlacesSearchService.get_business_details(@business.google_place_id)
          
          if result[:success]
            render json: {
              connected: true,
              place_id: @business.google_place_id,
              business: result[:business]
            }
          else
            # Place ID exists but may be invalid
            render json: {
              connected: true,
              place_id: @business.google_place_id,
              error: 'Unable to verify Google Business connection',
              warning: 'Your Google Place ID may be invalid or the business may no longer exist'
            }
          end
        else
          render json: { connected: false }
        end
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business status error: #{e.message}"
        render json: { 
          connected: @business.google_place_id.present?,
          place_id: @business.google_place_id,
          error: 'Unable to check connection status'
        }
      end

      # Calendar Integration Actions
      
      def calendar_integration_show
        @calendar_connection = current_business.calendar_connections.find(params[:calendar_integration_id])
        @sync_logs = CalendarSyncLog.joins(:calendar_event_mapping)
                                   .where(calendar_event_mappings: { calendar_connection_id: @calendar_connection.id })
                                   .includes(calendar_event_mapping: [:booking, :calendar_connection])
                                   .order(created_at: :desc)
                                   .limit(20)
      end
      
      def calendar_integration_connect
        provider = params[:provider]
        staff_member_id = params[:staff_member_id]
        
        unless available_providers.include?(provider)
          redirect_to business_manager_settings_integrations_path,
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
          redirect_to business_manager_settings_integrations_path,
                      alert: "#{provider.humanize} Calendar is already connected for #{staff_member.name}"
          return
        end
        
        if provider == 'caldav'
          # CalDAV uses manual setup, redirect to setup form
          redirect_to calendar_integration_new_caldav_business_manager_settings_integrations_path(staff_member_id: staff_member_id)
        else
          # OAuth providers (Google, Microsoft)
          oauth_handler = Calendar::OauthHandler.new
          scheme = request.ssl? ? 'https' : 'http'
          host = Rails.application.config.main_domain || request.host
          # Append port only if host does NOT already include one or is on standard ports
          port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
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
            redirect_to business_manager_settings_integrations_path,
                        alert: "Failed to initiate calendar connection: #{error_message}"
          end
        end
      end
      
      def calendar_integration_new_caldav
        @staff_member = current_business.staff_members.find(params[:staff_member_id])
        @caldav_providers = Calendar::CaldavFactory.available_providers
        @calendar_connection = CalendarConnection.new(
          business: current_business,
          staff_member: @staff_member,
          provider: :caldav
        )
      end
      
      def calendar_integration_create_caldav
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
              redirect_to business_manager_settings_integrations_path,
                          notice: "Successfully connected #{@calendar_connection.provider_display_name} for #{@staff_member.name}"
            else
              render :calendar_integration_new_caldav
            end
          else
            @calendar_connection.errors.add(:base, test_result[:message])
            render :calendar_integration_new_caldav
          end
        else
          render :calendar_integration_new_caldav
        end
      end
      
      def calendar_integration_test_caldav
        result = Calendar::CaldavFactory.test_connection(
          params[:username],
          params[:password],
          params[:url],
          params[:provider_type]
        )
        
        render json: result
      end

      def calendar_integration_destroy
        @calendar_connection = current_business.calendar_connections.find(params[:calendar_integration_id])
        provider_name = @calendar_connection.provider_display_name
        staff_name = @calendar_connection.staff_member.name
        
        # Remove default calendar connection reference first
        staff_member = @calendar_connection.staff_member
        if staff_member.default_calendar_connection == @calendar_connection
          staff_member.update(default_calendar_connection: nil)
        end
        
        @calendar_connection.destroy
        
        redirect_to business_manager_settings_integrations_path,
                    notice: "#{provider_name} calendar connection removed for #{staff_name}"
      end
      
      def calendar_integration_toggle_default
        @calendar_connection = current_business.calendar_connections.find(params[:calendar_integration_id])
        staff_member = @calendar_connection.staff_member
        
        if staff_member.default_calendar_connection == @calendar_connection
          staff_member.update(default_calendar_connection: nil)
          message = "Removed default calendar setting"
        else
          staff_member.update(default_calendar_connection: @calendar_connection)
          message = "Set as default calendar for #{staff_member.name}"
        end
        
        redirect_to business_manager_settings_integrations_path, notice: message
      end
      
      def calendar_integration_resync
        @calendar_connection = current_business.calendar_connections.find(params[:calendar_integration_id])
        # Enqueue background job to resync this connection's events
        Calendar::ImportAvailabilityJob.perform_later(@calendar_connection.staff_member.id)
        
        # Also sync any pending bookings for this staff member
        pending_bookings = @calendar_connection.staff_member.bookings
                                             .where(calendar_event_status: [:not_synced, :sync_pending])
                                             .limit(10)
        
        pending_bookings.each do |booking|
          Calendar::SyncBookingJob.perform_later(booking.id)
        end
        
        redirect_to business_manager_settings_integrations_path,
                    notice: "Calendar resync initiated for #{@calendar_connection.staff_member.name}"
      end
      
      def calendar_integration_batch_sync
        # Trigger batch sync for all active calendar connections
        Calendar::BatchSyncJob.perform_later(current_business.id, { 'action' => 'sync_pending' })
        
        redirect_to business_manager_settings_integrations_path,
                    notice: "Batch calendar sync initiated for all staff members"
      end
      
      def calendar_integration_import_availability
        # Import availability for all staff with calendar connections
        Calendar::BatchSyncJob.perform_later(current_business.id, { 'action' => 'import_all_availability' })
        
        redirect_to business_manager_settings_integrations_path,
                    notice: "Availability import initiated for all connected calendars"
      end

      private

      def set_business
        @business = current_business
        raise ActiveRecord::RecordNotFound unless @business
      end

      def authorize_business_settings
        authorize @business, :update_settings?, policy_class: ::Settings::BusinessPolicy
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
  end
end