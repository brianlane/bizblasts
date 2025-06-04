module BusinessManager
  module Settings
    class LocationsController < ApplicationController
      before_action :authenticate_user!
      before_action :set_business
      before_action :check_tier_access, only: [:new, :create]
      before_action :set_location, only: [:edit, :update, :destroy]
      before_action :ensure_default_location, only: [:index]

      layout 'business_manager'

      def index
        @locations = policy_scope([:business_manager, :settings, @current_business.locations])
      end

      def new
        @location = @current_business.locations.build
        authorize [:business_manager, :settings, @location]
      end

      def create
        @location = @current_business.locations.build(location_params)
        authorize [:business_manager, :settings, @location]
        if @location.save
          redirect_to business_manager_settings_locations_path, notice: 'Location was successfully created.'
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize [:business_manager, :settings, @location]
      end

      def update
        authorize [:business_manager, :settings, @location]
        
        # Process the location params
        processed_params = process_location_params(location_params)
        
        if @location.update(processed_params)
          # Sync changes to business model if this is the default location and the sync checkbox is checked
          if @location == @current_business.default_location && params[:sync_to_business] == '1'
            sync_with_business
            # Prepare locations for index render
            @locations = policy_scope([:business_manager, :settings, @current_business.locations])
            # Show notice immediately
            flash.now[:notice] = 'Location was successfully updated and synced with business information.'
            render :index
          else
            redirect_to business_manager_settings_locations_path, notice: 'Location was successfully updated.'
          end
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize [:business_manager, :settings, @location]
        @location.destroy
        redirect_to business_manager_settings_locations_url, notice: 'Location was successfully deleted.'
      end

      private

      def set_business
        @current_business = current_user.business
      end

      def set_location
        @location = @current_business.locations.find(params[:id])
      end

      def location_params
        # Permit hours as either a raw JSON string or nested hash for JSONB column
        params.require(:location).permit(:name, :address, :city, :state, :zip, :hours, hours: {})
      end
      
      # Sync main location data back to the business model
      def sync_with_business
        @current_business.update_columns(
          address: @location.address,
          city: @location.city,
          state: @location.state,
          zip: @location.zip,
          hours: @location.hours
        )
        Rails.logger.info "[LOCATIONS] Synced default location ##{@location.id} info to business ##{@current_business.id}"
      end
      
      # Ensure that every business has at least one default location
      def ensure_default_location
        return if @current_business.locations.exists?
        
        # Create a default location using business info
        # Default business hours (9am-5pm Monday-Friday, 10am-2pm Saturday, closed Sunday)
        default_hours = {
          "monday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
          "tuesday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
          "wednesday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
          "thursday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
          "friday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
          "saturday" => { "open" => "10:00", "close" => "14:00", "closed" => false },
          "sunday" => { "open" => "00:00", "close" => "00:00", "closed" => true }
        }
        
        # Use business hours if available, otherwise use default
        hours = @current_business.hours.present? ? @current_business.hours : default_hours
        
        default_location = @current_business.locations.create!(
          name: "Main Location",
          address: @current_business.address,
          city: @current_business.city,
          state: @current_business.state,
          zip: @current_business.zip,
          hours: hours
        )
        
        Rails.logger.info "[LOCATIONS] Created default location ##{default_location.id} for business ##{@current_business.id}"
      rescue => e
        Rails.logger.error "[LOCATIONS] Failed to create default location: #{e.message}"
        flash.now[:alert] = "We couldn't create a default location automatically. Please create one manually."
      end
      
      # Process the location parameters to ensure JSON is handled correctly
      def process_location_params(params)
        processed = params.dup
        
        # Handle the hours parameter if it's a string
        if processed[:hours].is_a?(String)
          begin
            # Try to parse it as JSON to clean it up
            json_data = JSON.parse(processed[:hours])
            processed[:hours] = json_data
          rescue JSON::ParserError => e
            # If it can't be parsed, log the error but continue
            Rails.logger.error "[LOCATIONS] Error parsing hours JSON: #{e.message}"
          end
        end
        
        processed
      end

      # Check if current business has access to multiple locations (Premium tier only)
      def check_tier_access
        unless @current_business.premium_tier?
          flash[:alert] = "Multiple locations are available on the Premium plan. Upgrade your subscription to add additional locations."
          redirect_to business_manager_settings_subscription_path
        end
      end
    end
  end
end 