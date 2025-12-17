# frozen_string_literal: true

module BusinessManager
  module Settings
    class IntegrationsController < BusinessManager::BaseController
      before_action :set_business
      before_action :authorize_business_settings

      # GET /manage/settings/integrations
      def index
        # Show integrations overview including Google Business Reviews, Calendar, and Video Meeting Integrations
        @staff_members = current_business.staff_members.active.includes(:calendar_connections, :video_meeting_connections, :user)
        @calendar_connections = current_business.calendar_connections.includes(:staff_member).active
        @video_meeting_connections = current_business.video_meeting_connections.includes(:staff_member).active
        @sync_statistics = calculate_sync_statistics
        @providers = available_providers
        @video_providers = available_video_providers

        # Accounting + Payroll integrations
        @quickbooks_connection = current_business.quickbooks_connection
        @quickbooks_export_runs = current_business.quickbooks_export_runs.order(created_at: :desc).limit(10)
        @adp_payroll_config = current_business.adp_payroll_export_config || current_business.build_adp_payroll_export_config
        @adp_payroll_export_runs = current_business.adp_payroll_export_runs.order(created_at: :desc).limit(10)

        # Email Marketing integrations (Mailchimp, Constant Contact)
        @mailchimp_connection = current_business.email_marketing_connections.mailchimp.first
        @constant_contact_connection = current_business.email_marketing_connections.constant_contact.first
        @email_marketing_providers = available_email_marketing_providers
        @mailchimp_sync_logs = @mailchimp_connection&.sync_logs&.recent&.limit(5) || []
        @constant_contact_sync_logs = @constant_contact_connection&.sync_logs&.recent&.limit(5) || []

        # ADP payroll preview (optional UI)
        @adp_preview_rows = []
        @adp_preview_summary = nil
        @adp_preview_errors = []
        @adp_preview_totals_by_employee = {}
        @adp_preview_grand_total = 0.0

        if params[:adp_preview] == '1' && params[:adp_range_start].present? && params[:adp_range_end].present?
          begin
            range_start = Date.iso8601(params[:adp_range_start].to_s)
            range_end = Date.iso8601(params[:adp_range_end].to_s)

            builder = Payroll::AdpPreviewBuilder.new(business: current_business, config: @adp_payroll_config)
            rows, summary, report = builder.build(range_start: range_start, range_end: range_end)

            @adp_preview_rows = rows
            @adp_preview_summary = summary
            @adp_preview_errors = Array(report[:errors])

            totals = Hash.new(0.0)
            rows.each do |r|
              totals[r[:employee_id]] += r[:hours].to_f
            end
            @adp_preview_totals_by_employee = totals
            @adp_preview_grand_total = totals.values.sum.round(2)
          rescue Date::Error
            flash.now[:alert] = 'Invalid preview date range. Please use YYYY-MM-DD.'
          rescue => e
            Rails.logger.error("[IntegrationsController] ADP preview error: #{e.message}")
            flash.now[:alert] = 'Failed to generate payroll preview. Please try again.'
          end
        end
        
        # SECURITY FIX (CWE-598): Read OAuth flash messages from session instead of URL parameters
        # This prevents sensitive data from being exposed in browser history, server logs,
        # referrer headers, and proxy caches.
        #
        # Session-based approach is secure because:
        # - Session data is stored server-side, not in URLs
        # - Messages are immediately cleared after display
        # - Consistent with OAuth state management pattern
        # - Aligns with secure CalendarOauthController pattern
        if session[:oauth_flash_notice]
          flash.now[:notice] = session.delete(:oauth_flash_notice)
        elsif session[:oauth_flash_alert]
          flash.now[:alert] = session.delete(:oauth_flash_alert)
        end
        
        # Handle Google Business Profile account selection
        if params[:show_google_accounts] && session[:google_business_accounts]
          @google_business_accounts = session[:google_business_accounts]
          @google_oauth_tokens = session[:google_oauth_tokens]
        end
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

      # GET /manage/settings/integrations/google-business/search-nearby
      def google_business_search_nearby
        latitude = params[:latitude]&.strip
        longitude = params[:longitude]&.strip
        query = params[:query]&.strip
        radius = params[:radius]&.to_i || 1000
        
        if latitude.blank? || longitude.blank?
          render json: { error: 'Latitude and longitude are required' }, status: :bad_request
          return
        end
        
        result = GooglePlacesSearchService.search_nearby(latitude, longitude, query, radius)
        render json: result
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business nearby search error: #{e.message}"
        render json: { error: 'Failed to search nearby businesses' }, status: :internal_server_error
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
          }, status: :unprocessable_content
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
          }, status: :unprocessable_content
        end
      rescue => e
        Rails.logger.error "[IntegrationsController] Google Business disconnect error: #{e.message}"
        render json: { error: 'Disconnection failed' }, status: :internal_server_error
      end

      # POST /manage/settings/integrations/google-business/connect-manual
      def google_business_connect_manual
        business_name = params[:business_name]&.strip
        business_address = params[:business_address]&.strip
        business_phone = params[:business_phone]&.strip
        business_website = params[:business_website]&.strip
        
        if business_name.blank?
          render json: { error: 'Business name is required for manual entry' }, status: :bad_request
          return
        end
        
        # Store manual business information
        manual_business_data = {
          name: business_name,
          address: business_address,
          phone: business_phone,
          website: business_website,
          manual_entry: true,
          connected_at: Time.current
        }
        
        # Update business with manual Google Business info (no Place ID)
        if @business.update(
          google_business_name: business_name,
          google_business_address: business_address,
          google_business_phone: business_phone,
          google_business_website: business_website,
          google_business_manual: true,
          google_place_id: nil # Explicitly no Place ID for manual entries
        )
          Rails.logger.info "[GoogleBusiness] Manually connected business #{@business.id}: #{business_name}"
          
          render json: { 
            success: true, 
            message: 'Google Business information saved successfully',
            business: manual_business_data,
            note: 'Reviews cannot be automatically fetched for manually entered businesses'
          }
        else
          render json: { 
            error: 'Failed to save Google Business information', 
            details: @business.errors.full_messages 
          }, status: :unprocessable_content
        end
      rescue => e
        Rails.logger.error "[IntegrationsController] Manual Google Business connect error: #{e.message}"
        render json: { error: 'Manual connection failed' }, status: :internal_server_error
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

      # POST /manage/settings/integrations/lookup-place-id
      # Initiates async extraction of Place ID from Google Maps URL
      def lookup_place_id
        google_maps_url = params[:input]&.strip

        if google_maps_url.blank?
          return render json: { success: false, error: 'Please enter a Google Maps URL' }, status: :unprocessable_content
        end

        normalized_url = normalize_google_maps_url(google_maps_url)

        # Check if normalization failed (encoding error)
        if normalized_url.nil?
          return render json: { success: false, error: 'Invalid URL encoding. Please check your URL and try again.' }, status: :unprocessable_content
        end

        # SECURITY: Strict URL validation to prevent injection attacks
        unless valid_google_maps_url?(normalized_url)
          return render json: {
            success: false,
            error: 'Invalid Google Maps URL. Must be from google.com or google.co domain.'
          }, status: :unprocessable_content
        end

        # SECURITY: Rate limiting - check user-specific limit (5 per hour)
        rate_limit_key = "place_id_extraction:user:#{current_user.id}"
        current_count = Rails.cache.read(rate_limit_key).to_i

        if current_count >= 5
          return render json: {
            success: false,
            error: 'Rate limit exceeded. You can extract 5 Place IDs per hour. Please try again later.'
          }, status: :too_many_requests
        end

        # Increment rate limit counter (atomic operation)
        new_count = Rails.cache.increment(rate_limit_key, 1, expires_in: 1.hour) || 1
        Rails.cache.write(rate_limit_key, 1, expires_in: 1.hour) if new_count == 1

        # Generate unique job ID
        job_id = SecureRandom.uuid

        # Start background job to extract Place ID
        PlaceIdExtractionJob.perform_later(job_id, normalized_url)

        Rails.logger.info "[IntegrationsController] Started Place ID extraction job: #{job_id} for user: #{current_user.id}"

        # Return job ID for polling
        render json: {
          success: true,
          job_id: job_id,
          message: 'Extraction started. This may take 5-10 seconds...'
        }
      rescue StandardError => e
        Rails.logger.error "[IntegrationsController] Error starting Place ID extraction: #{e.message}"
        render json: {
          success: false,
          error: 'Failed to start extraction. Please try again.'
        }, status: :internal_server_error
      end

      # GET /manage/settings/integrations/check-place-id-status/:job_id
      # Check status of Place ID extraction job
      def check_place_id_status
        job_id = params[:job_id]

        if job_id.blank?
          return render json: { success: false, error: 'Job ID is required' }, status: :bad_request
        end

        # Retrieve status from cache
        status_data = Rails.cache.read("place_id_extraction:#{job_id}")

        unless status_data
          return render json: {
            success: false,
            status: 'not_found',
            error: 'Job not found or expired'
          }, status: :not_found
        end

        render json: {
          success: true,
          status: status_data[:status],
          place_id: status_data[:place_id],
          message: status_data[:message],
          error: status_data[:error]
        }
      rescue StandardError => e
        Rails.logger.error "[IntegrationsController] Error checking Place ID status: #{e.message}"
        render json: {
          success: false,
          error: 'Failed to check status'
        }, status: :internal_server_error
      end

      # GET /manage/settings/integrations/google-business/oauth/authorize
      def google_business_oauth_authorize
        # Generate OAuth URL for Google Business Profile API using unified OAuth credentials
        client_id = GoogleOauthCredentials.client_id
        redirect_uri = google_business_oauth_callback_url
        
        unless GoogleOauthCredentials.configured?
          redirect_to business_manager_settings_integrations_path,
                      alert: 'Google OAuth not configured. Please contact support.'
          return
        end
        
        # Store business ID and user ID in session for callback
        session[:oauth_business_id] = @business.id
        session[:oauth_user_id] = current_user.id
        
        # OAuth scopes for Google Business Profile API
        scopes = [
          'https://www.googleapis.com/auth/business.manage'
        ].join(' ')
        
        # Generate state parameter for security
        state = SecureRandom.hex(32)
        session[:oauth_state] = state
        
        auth_url = "https://accounts.google.com/o/oauth2/auth?" \
                   "client_id=#{CGI.escape(client_id)}&" \
                   "redirect_uri=#{CGI.escape(redirect_uri)}&" \
                   "scope=#{CGI.escape(scopes)}&" \
                   "response_type=code&" \
                   "access_type=offline&" \
                   "prompt=consent&" \
                   "state=#{state}"
        
        Rails.logger.info "[GoogleBusinessOAuth] Redirecting to OAuth for business #{@business.id}"
        redirect_to auth_url, allow_other_host: true
      rescue => e
        Rails.logger.error "[GoogleBusinessOAuth] Authorization error: #{e.message}"
        redirect_to business_manager_settings_integrations_path,
                    alert: 'Failed to start OAuth process. Please try again.'
      end

      # ----------------------------------------------------------------------
      # QuickBooks Online Integration Actions
      # ----------------------------------------------------------------------

      # GET /manage/settings/integrations/quickbooks/oauth/authorize
      def quickbooks_oauth_authorize
        unless QuickbooksOauthCredentials.configured?
          redirect_to business_manager_settings_integrations_path,
                      alert: 'QuickBooks OAuth not configured. Please contact support.'
          return
        end

        oauth_handler = Quickbooks::OauthHandler.new
        redirect_uri = quickbooks_oauth_callback_url

        auth_url = oauth_handler.authorization_url(current_business.id, redirect_uri)

        if auth_url
          redirect_to auth_url, allow_other_host: true
        else
          redirect_to business_manager_settings_integrations_path,
                      alert: oauth_handler.errors.full_messages.to_sentence.presence || 'Failed to start QuickBooks connection.'
        end
      rescue => e
        Rails.logger.error "[QuickBooksOAuth] Authorization error: #{e.message}"
        redirect_to business_manager_settings_integrations_path,
                    alert: 'Failed to start QuickBooks OAuth process. Please try again.'
      end

      # DELETE /manage/settings/integrations/quickbooks/disconnect
      def quickbooks_disconnect
        connection = current_business.quickbooks_connection

        if connection
          connection.destroy
          redirect_to business_manager_settings_integrations_path, notice: 'QuickBooks disconnected.'
        else
          redirect_to business_manager_settings_integrations_path, alert: 'No QuickBooks connection found.'
        end
      end

      # POST /manage/settings/integrations/quickbooks/exports/invoices
      def quickbooks_export_invoices
        connection = current_business.quickbooks_connection
        unless connection&.active?
          redirect_to business_manager_settings_integrations_path, alert: 'QuickBooks is not connected.'
          return
        end

        range_start = Date.iso8601(params[:range_start].to_s)
        range_end = Date.iso8601(params[:range_end].to_s)
        statuses = Array(params[:invoice_statuses].presence || %w[paid]).map(&:to_s)

        export_run = current_business.quickbooks_export_runs.create!(
          user: current_user,
          status: :queued,
          export_type: 'invoices',
          filters: {
            range_start: range_start.iso8601,
            range_end: range_end.iso8601,
            invoice_statuses: statuses,
            export_payments: params[:export_payments] == '1'
          }
        )

        Quickbooks::ExportInvoicesJob.perform_later(export_run.id)

        redirect_to business_manager_settings_integrations_path, notice: 'QuickBooks invoice export started.'
      rescue Date::Error
        redirect_to business_manager_settings_integrations_path, alert: 'Invalid date range. Please use YYYY-MM-DD.'
      rescue ActiveRecord::RecordInvalid => e
        redirect_to business_manager_settings_integrations_path, alert: e.record.errors.full_messages.to_sentence
      end

      # PATCH /manage/settings/integrations/quickbooks/config
      def quickbooks_config_update
        connection = current_business.quickbooks_connection
        unless connection&.active?
          redirect_to business_manager_settings_integrations_path, alert: 'QuickBooks is not connected.'
          return
        end

        incoming = quickbooks_config_params.to_h

        # Ensure checkbox values can be turned OFF: when unchecked Rails may not send it unless
        # a hidden field is present. We also defensively treat missing as false.
        update_existing = params.dig(:quickbooks, :update_existing_invoices).to_s == '1'

        new_config = connection.config.merge(incoming).merge(
          'update_existing_invoices' => update_existing
        )

        connection.update!(config: new_config)

        redirect_to business_manager_settings_integrations_path, notice: 'QuickBooks settings updated.'
      rescue ActiveRecord::RecordInvalid => e
        redirect_to business_manager_settings_integrations_path, alert: e.record.errors.full_messages.to_sentence
      end

      # POST /manage/settings/integrations/quickbooks/exports/:id/retry
      def quickbooks_export_retry_failed
        prior = current_business.quickbooks_export_runs.find(params[:id])

        failures = Array(prior.error_report['failures'])
        invoice_ids = failures.map { |f| f['invoice_id'] || f[:invoice_id] }.compact

        if invoice_ids.empty?
          redirect_to business_manager_settings_integrations_path, alert: 'No failed invoices to retry.'
          return
        end

        export_run = current_business.quickbooks_export_runs.create!(
          user: current_user,
          status: :queued,
          export_type: 'invoices',
          filters: prior.filters.merge('invoice_ids' => invoice_ids)
        )

        Quickbooks::ExportInvoicesJob.perform_later(export_run.id)

        redirect_to business_manager_settings_integrations_path, notice: 'Retry started for failed invoices.'
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

      # Video Meeting Integration Actions

      # POST /manage/settings/integrations/video-integrations/connect
      def video_integration_connect
        provider = params[:provider]
        staff_member_id = params[:staff_member_id]

        unless %w[zoom google_meet].include?(provider)
          redirect_to business_manager_settings_integrations_path,
                      alert: "Unsupported video meeting provider: #{provider}"
          return
        end

        staff_member = current_business.staff_members.find(staff_member_id)

        # Check if connection already exists
        existing_connection = staff_member.video_meeting_connections
                                         .where(provider: provider)
                                         .active
                                         .first

        if existing_connection
          provider_name = existing_connection.provider_name
          redirect_to business_manager_settings_integrations_path,
                      alert: "#{provider_name} is already connected for #{staff_member.name}"
          return
        end

        # OAuth flow
        oauth_handler = VideoMeeting::OauthHandler.new
        redirect_uri = build_video_oauth_redirect_uri(provider)

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
                      alert: "Failed to initiate video meeting connection: #{error_message}"
        end
      end

      # DELETE /manage/settings/integrations/video-integrations/:id
      def video_integration_destroy
        @video_connection = current_business.video_meeting_connections.find(params[:id])
        provider_name = @video_connection.provider_name
        staff_name = @video_connection.staff_member.name

        @video_connection.destroy

        redirect_to business_manager_settings_integrations_path,
                    notice: "#{provider_name} video meeting connection removed for #{staff_name}"
      end

      # GET /manage/settings/integrations/video-integrations/:id/status
      def video_integration_status
        @video_connection = current_business.video_meeting_connections.find(params[:id])

        render json: {
          id: @video_connection.id,
          provider: @video_connection.provider,
          provider_name: @video_connection.provider_name,
          active: @video_connection.active?,
          connected_at: @video_connection.connected_at,
          last_used_at: @video_connection.last_used_at,
          token_valid: !@video_connection.token_expired?,
          staff_member: {
            id: @video_connection.staff_member.id,
            name: @video_connection.staff_member.name
          }
        }
      end

      # POST /manage/settings/integrations/video-integrations/link-from-calendar
      # Creates a Google Meet connection from an existing Google Calendar connection
      # This allows reusing the same Google account without a separate OAuth flow
      def video_integration_link_from_calendar
        staff_member_id = params[:staff_member_id]
        staff_member = current_business.staff_members.find(staff_member_id)

        # Find existing Google Calendar connection
        calendar_connection = staff_member.calendar_connections
                                         .where(provider: 'google')
                                         .active
                                         .first

        unless calendar_connection
          redirect_to business_manager_settings_integrations_path,
                      alert: "No Google Calendar connection found for #{staff_member.name}. Please connect Google Calendar first or use a separate Google Meet connection."
          return
        end

        # Check if Google Meet is already connected
        existing_meet = staff_member.video_meeting_connections
                                   .where(provider: :google_meet)
                                   .active
                                   .first

        if existing_meet
          redirect_to business_manager_settings_integrations_path,
                      alert: "Google Meet is already connected for #{staff_member.name}"
          return
        end

        begin
          VideoMeetingConnection.create_from_calendar_connection!(calendar_connection)
          redirect_to business_manager_settings_integrations_path,
                      notice: "Google Meet connected for #{staff_member.name} using existing Google Calendar account"
        rescue => e
          Rails.logger.error("[VideoIntegration] Failed to link from calendar: #{e.message}")
          redirect_to business_manager_settings_integrations_path,
                      alert: "Failed to connect Google Meet: #{e.message}"
        end
      end

      # ----------------------------------------------------------------------
      # Payroll Export (ADP) Actions
      # ----------------------------------------------------------------------

      # PATCH /manage/settings/integrations/adp-payroll/config
      def adp_payroll_config_update
        config = current_business.adp_payroll_export_config || current_business.build_adp_payroll_export_config

        if config.update(adp_payroll_config_params)
          redirect_to business_manager_settings_integrations_path, notice: 'Payroll export settings updated.'
        else
          redirect_to business_manager_settings_integrations_path, alert: config.errors.full_messages.to_sentence
        end
      end

      # POST /manage/settings/integrations/adp-payroll/exports
      def adp_payroll_export_create
        range_start = Date.iso8601(params[:range_start].to_s)
        range_end = Date.iso8601(params[:range_end].to_s)

        export_run = current_business.adp_payroll_export_runs.create!(
          user: current_user,
          status: :queued,
          range_start: range_start,
          range_end: range_end,
          options: {
            requested_at: Time.current.iso8601
          }
        )

        Payroll::GenerateAdpExportJob.perform_later(export_run.id)

        redirect_to business_manager_settings_integrations_path, notice: 'Payroll export started. It will be ready for download shortly.'
      rescue Date::Error
        redirect_to business_manager_settings_integrations_path, alert: 'Invalid date range. Please use YYYY-MM-DD.'
      rescue ActiveRecord::RecordInvalid => e
        redirect_to business_manager_settings_integrations_path, alert: e.record.errors.full_messages.to_sentence
      end

      # GET /manage/settings/integrations/adp-payroll/exports/:id/download
      def adp_payroll_export_download
        export_run = current_business.adp_payroll_export_runs.find(params[:id])

        unless export_run.succeeded? && export_run.csv_data.present?
          redirect_to business_manager_settings_integrations_path, alert: 'Export is not ready yet. Please try again in a moment.'
          return
        end

        filename = "adp-payroll-export-#{export_run.range_start}-to-#{export_run.range_end}.csv"
        send_data export_run.csv_data, filename: filename, type: 'text/csv'
      end

      # ----------------------------------------------------------------------
      # Email Marketing Integration Actions (Mailchimp & Constant Contact)
      # ----------------------------------------------------------------------

      # GET /manage/settings/integrations/mailchimp/oauth/authorize
      def mailchimp_oauth_authorize
        unless MailchimpOauthCredentials.configured?
          redirect_to business_manager_settings_integrations_path,
                      alert: 'Mailchimp OAuth not configured. Please contact support.'
          return
        end

        oauth_handler = EmailMarketing::Mailchimp::OauthHandler.new
        redirect_uri = email_marketing_oauth_callback_url('mailchimp')

        auth_url = oauth_handler.authorization_url(current_business.id, redirect_uri)

        if auth_url
          # NOTE: We don't store state in session because OAuth callback goes to main domain
          # which won't have access to tenant-scoped session. CSRF protection is provided
          # by the cryptographically-signed state parameter verified in the callback handler.
          redirect_to auth_url, allow_other_host: true
        else
          redirect_to business_manager_settings_integrations_path,
                      alert: oauth_handler.errors.full_messages.to_sentence.presence || 'Failed to start Mailchimp connection.'
        end
      rescue StandardError => e
        Rails.logger.error "[MailchimpOAuth] Authorization error: #{e.message}"
        redirect_to business_manager_settings_integrations_path,
                    alert: 'Failed to start Mailchimp OAuth process. Please try again.'
      end

      # DELETE /manage/settings/integrations/mailchimp/disconnect
      def mailchimp_disconnect
        connection = current_business.email_marketing_connections.mailchimp.first

        if connection
          connection.destroy
          redirect_to business_manager_settings_integrations_path, notice: 'Mailchimp disconnected successfully.'
        else
          redirect_to business_manager_settings_integrations_path, alert: 'No Mailchimp connection found.'
        end
      end

      # GET /manage/settings/integrations/constant-contact/oauth/authorize
      def constant_contact_oauth_authorize
        unless ConstantContactOauthCredentials.configured?
          redirect_to business_manager_settings_integrations_path,
                      alert: 'Constant Contact OAuth not configured. Please contact support.'
          return
        end

        oauth_handler = EmailMarketing::ConstantContact::OauthHandler.new
        redirect_uri = email_marketing_oauth_callback_url('constant-contact')

        auth_url = oauth_handler.authorization_url(current_business.id, redirect_uri)

        if auth_url
          # NOTE: We don't store state in session because OAuth callback goes to main domain
          # which won't have access to tenant-scoped session. CSRF protection is provided
          # by the cryptographically-signed state parameter verified in the callback handler.
          redirect_to auth_url, allow_other_host: true
        else
          redirect_to business_manager_settings_integrations_path,
                      alert: oauth_handler.errors.full_messages.to_sentence.presence || 'Failed to start Constant Contact connection.'
        end
      rescue StandardError => e
        Rails.logger.error "[ConstantContactOAuth] Authorization error: #{e.message}"
        redirect_to business_manager_settings_integrations_path,
                    alert: 'Failed to start Constant Contact OAuth process. Please try again.'
      end

      # DELETE /manage/settings/integrations/constant-contact/disconnect
      def constant_contact_disconnect
        connection = current_business.email_marketing_connections.constant_contact.first

        if connection
          connection.destroy
          redirect_to business_manager_settings_integrations_path, notice: 'Constant Contact disconnected successfully.'
        else
          redirect_to business_manager_settings_integrations_path, alert: 'No Constant Contact connection found.'
        end
      end

      # GET /manage/settings/integrations/email-marketing/:provider/lists
      def email_marketing_lists
        provider = normalize_email_marketing_provider(params[:provider])
        connection = current_business.email_marketing_connections.find_by(provider: provider)

        unless connection&.connected?
          render json: { error: 'Not connected' }, status: :unprocessable_entity
          return
        end

        lists = connection.available_lists
        render json: { lists: lists }
      rescue StandardError => e
        Rails.logger.error "[EmailMarketing] Failed to fetch lists: #{e.message}"
        render json: { error: 'Failed to fetch lists' }, status: :internal_server_error
      end

      # PATCH /manage/settings/integrations/email-marketing/:provider/config
      def email_marketing_update_config
        provider = normalize_email_marketing_provider(params[:provider])
        connection = current_business.email_marketing_connections.find_by(provider: provider)

        unless connection
          redirect_to business_manager_settings_integrations_path, alert: 'Connection not found.'
          return
        end

        if connection.update(email_marketing_config_params)
          redirect_to business_manager_settings_integrations_path, notice: "#{connection.provider_name} settings updated."
        else
          redirect_to business_manager_settings_integrations_path, alert: connection.errors.full_messages.to_sentence
        end
      end

      # POST /manage/settings/integrations/email-marketing/:provider/sync
      def email_marketing_sync
        provider = normalize_email_marketing_provider(params[:provider])
        connection = current_business.email_marketing_connections.find_by(provider: provider)

        unless connection&.connected?
          redirect_to business_manager_settings_integrations_path, alert: 'Not connected to this provider.'
          return
        end

        # Require a default list to be configured before syncing
        unless connection.default_list_id.present?
          redirect_to business_manager_settings_integrations_path,
                      alert: "Please select a default list in #{connection.provider_name} before syncing."
          return
        end

        # Default to full sync since UI says "sync all your customers"
        # Use 'incremental' only when explicitly requested
        sync_type = params[:sync_type] || 'full'

        EmailMarketing::SyncContactsJob.perform_later(
          connection.id,
          { sync_type: sync_type, list_id: connection.default_list_id }
        )

        redirect_to business_manager_settings_integrations_path,
                    notice: "#{connection.provider_name} sync started. This may take a few minutes."
      end

      # GET /manage/settings/integrations/email-marketing/:provider/sync-status
      def email_marketing_sync_status
        provider = normalize_email_marketing_provider(params[:provider])
        connection = current_business.email_marketing_connections.find_by(provider: provider)

        unless connection
          render json: { error: 'Connection not found' }, status: :not_found
          return
        end

        recent_logs = connection.sync_logs.recent.limit(5).map do |log|
          {
            id: log.id,
            sync_type: log.sync_type,
            status: log.status,
            direction: log.direction,
            contacts_synced: log.contacts_synced,
            contacts_failed: log.contacts_failed,
            started_at: log.started_at,
            completed_at: log.completed_at,
            duration: log.duration_formatted
          }
        end

        render json: {
          connected: connection.connected?,
          last_synced_at: connection.last_synced_at,
          total_contacts_synced: connection.total_contacts_synced,
          recent_syncs: recent_logs
        }
      end

      private

      def set_business
        @business = current_business
        raise ActiveRecord::RecordNotFound unless @business
      end

      def authorize_business_settings
        authorize @business, :update_settings?, policy_class: ::Settings::BusinessPolicy
      end
      
      def google_business_oauth_callback_url
        # Use the global OAuth callback route (not tenant-specific)
        # Follow the same pattern as calendar OAuth for consistency
        scheme = request.ssl? ? 'https' : 'http'
        host = Rails.application.config.main_domain.presence || request.host
        # Append port only if host does NOT already include one or is on standard ports
        port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                     ''
                   else
                     ":#{request.port}"
                   end
        "#{scheme}://#{host}#{port_str}/oauth/google-business/callback"
      end

      def quickbooks_oauth_callback_url
        scheme = request.ssl? ? 'https' : 'http'
        host = Rails.application.config.main_domain.presence || request.host
        port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                     ''
                   else
                     ":#{request.port}"
                   end
        "#{scheme}://#{host}#{port_str}/oauth/quickbooks/callback"
      end

      def email_marketing_oauth_callback_url(provider)
        scheme = request.ssl? ? 'https' : 'http'
        host = Rails.application.config.main_domain.presence || request.host
        port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                     ''
                   else
                     ":#{request.port}"
                   end
        "#{scheme}://#{host}#{port_str}/oauth/email-marketing/#{provider}/callback"
      end

      def email_marketing_config_params
        params.require(:email_marketing_connection).permit(
          :default_list_id,
          :default_list_name,
          :sync_on_customer_create,
          :sync_on_customer_update,
          :receive_unsubscribe_webhooks,
          :sync_strategy
        )
      end

      # Normalize provider param to match enum format (e.g., 'constant-contact' -> 'constant_contact')
      # Routes use hyphenated format but enum uses underscores
      def normalize_email_marketing_provider(provider)
        provider.to_s.tr('-', '_')
      end

      def available_email_marketing_providers
        providers = []
        providers << 'mailchimp' if MailchimpOauthCredentials.configured?
        providers << 'constant_contact' if ConstantContactOauthCredentials.configured?
        providers
      end

      def available_providers
        providers = []
        
        # Check if Google OAuth credentials are configured (used for both Calendar and Business Profile)
        google_configured = GoogleOauthCredentials.configured?
        
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

      def available_video_providers
        providers = []

        # Zoom - check if credentials are configured
        if ENV['ZOOM_CLIENT_ID'].present? && ENV['ZOOM_CLIENT_SECRET'].present?
          providers << 'zoom'
        elsif Rails.env.development? || Rails.env.test?
          # Also check dev credentials
          if ENV['ZOOM_CLIENT_ID_DEV'].present? && ENV['ZOOM_CLIENT_SECRET_DEV'].present?
            providers << 'zoom'
          end
        end

        # Google Meet - uses same OAuth as Google Calendar
        providers << 'google_meet' if GoogleOauthCredentials.configured?

        providers
      end

      def build_video_oauth_redirect_uri(provider)
        scheme = request.ssl? ? 'https' : 'http'
        host = Rails.application.config.main_domain || request.host
        port_str = if host&.include?(':') || request.port.nil? || [80, 443].include?(request.port)
                     ''
                   else
                     ":#{request.port}"
                   end

        provider_path = case provider.to_s
                        when 'zoom' then 'zoom'
                        when 'google_meet' then 'google-meet'
                        else provider
                        end

        "#{scheme}://#{host}#{port_str}/oauth/video/#{provider_path}/callback"
      end

      def calculate_sync_statistics
        return {} if current_business.calendar_connections.empty?
        
        sync_coordinator = Calendar::SyncCoordinator.new
        sync_coordinator.sync_statistics(current_business, 24.hours.ago)
      end
      
      def calendar_connection_params
        params.require(:calendar_connection).permit(:provider, :staff_member_id)
      end

      def adp_payroll_config_params
        params.require(:adp_payroll_export_config).permit(
          :active,
          :rounding_minutes,
          :round_total_hours,
          config: [:default_pay_code, :timezone, { included_booking_statuses: [] }]
        )
      end

      def quickbooks_config_params
        params.require(:quickbooks).permit(
          :income_account_id,
          :default_sales_item_name,
          :customer_strategy,
          :update_existing_invoices
        )
      end

      # SECURITY: Strict URL validation for Place ID extraction
      # Prevents URL injection attacks by validating:
      # 1. Must be HTTPS
      # 2. Must be from google.com or google.co.* domain (not subdomain of attacker's domain)
      # 3. Must contain /maps/ in path
      def valid_google_maps_url?(url)
        return false if url.blank?

        begin
          uri = URI.parse(url)

          # Must be HTTPS (reject http://)
          return false unless uri.scheme == 'https'

          # Must be Google domain (not subdomain of attacker's domain)
          # Valid: google.com, www.google.com, google.co.uk, www.google.co.uk
          # Invalid: google.com.evil.com, evil.com/google.com/maps
          return false unless uri.host =~ /\A(www\.)?google\.(com|co\.[a-z]{2})\z/i

          # Must contain /maps/ in path
          return false unless uri.path&.include?('/maps/')

          true
        rescue URI::InvalidURIError => e
          Rails.logger.warn "[IntegrationsController] Invalid URI for Place ID extraction after normalization: #{e.message}"
          false
        end
      end

      # Percent-encode non-ASCII characters so Ruby's URI parser can handle mobile-smart quotes, emojis, etc.
      def normalize_google_maps_url(url)
        return url if url.blank? || url.ascii_only?

        begin
          encoded = url.each_char.map do |char|
            char.ascii_only? ? char : CGI.escape(char)
          end.join
          encoded
        rescue Encoding::UndefinedConversionError => e
          Rails.logger.warn "[IntegrationsController] Failed to normalize Google Maps URL: #{e.message}"
          nil
        end
      end
    end
  end
end
