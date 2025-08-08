# frozen_string_literal: true

module BusinessManager
  module Settings
    class IntegrationsController < BusinessManager::BaseController
      before_action :set_business
      before_action :authorize_business_settings

      # GET /manage/settings/integrations
      def index
        # Show integrations overview including Google Business Reviews
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

      private

      def set_business
        @business = current_business
        raise ActiveRecord::RecordNotFound unless @business
      end

      def authorize_business_settings
        authorize @business, :update_settings?, policy_class: ::Settings::BusinessPolicy
      end
    end
  end
end