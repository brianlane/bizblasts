# frozen_string_literal: true

# Controller to handle the public listing of businesses
class BusinessesController < ApplicationController
  # Skip user authentication for the index page
  skip_before_action :authenticate_user!, only: [:index]
  # No tenant context needed for the global business list
  # skip_before_action :set_tenant # Assuming set_tenant is not a global filter

  # Security: Add rate limiting for search queries (uncomment if using rack-attack)
  # before_action :check_search_rate_limit, only: [:index], if: -> { params[:search].present? }

  # GET /businesses
  def index
    # Get distinct, human-readable industries for filtering dropdown from enum values
    @industries = Business.industries.values.sort

    # Base query for active businesses
    businesses_query = Business.active

    # Apply description search with security measures
    if params[:search].present? && params[:search].strip.present?
      search_term = sanitize_search_input(params[:search])
      
      # Security: Limit search term length to prevent abuse
      if search_term.length > 100
        flash.now[:alert] = "Search term is too long. Please use fewer than 100 characters."
        search_term = search_term[0, 100]
      end
      
      # Security: Escape SQL wildcards in user input and add our own
      escaped_search = ActiveRecord::Base.sanitize_sql_like(search_term)
      search_pattern = "%#{escaped_search}%"
      businesses_query = businesses_query.where("description ILIKE ?", search_pattern)
    end

    # Apply industry filter with validation
    if params[:industry].present?
      # Security: Validate industry is from allowed list
      if @industries.include?(params[:industry])
        businesses_query = businesses_query.where(industry: params[:industry])
      else
        # Log suspicious activity
        Rails.logger.warn "[SECURITY] Invalid industry filter attempted: #{params[:industry]} from IP: #{request.remote_ip}"
        flash.now[:alert] = "Invalid industry filter."
      end
    end

    # Apply sorting with whitelist validation
    sort_column = case params[:sort]
                  when 'name' then :name
                  when 'date' then :created_at
                  else :name # Default sort
                  end
    
    # Security: Validate sort direction
    sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction].to_sym : :asc
    businesses_query = businesses_query.order(sort_column => sort_direction)

    # Security: Limit page parameter to reasonable range
    page_param = [params[:page].to_i, 1].max
    page_param = [page_param, 1000].min # Max 1000 pages to prevent enumeration attacks

    # Paginate results with security limits
    @businesses = businesses_query.page(page_param).per(25) # Limit to 25 per page
  end
  
  def show
    # Placeholder for showing a business
  end
  
  def new
    # Placeholder for new business form
  end
  
  def create
    # Placeholder for creating a business
  end
  
  def edit
    # Placeholder for editing a business
  end
  
  def update
    # Placeholder for updating a business
  end
  
  def destroy
    # Placeholder for deleting a business
  end

  private

  # Security: Sanitize search input
  def sanitize_search_input(input)
    # Remove potentially dangerous characters while keeping search functionality
    sanitized = input.strip
    
    # Remove excessive whitespace
    sanitized = sanitized.squeeze(' ')
    
    # Remove control characters but keep unicode letters/numbers/spaces/punctuation
    sanitized = sanitized.gsub(/[[:cntrl:]]/, '')
    
    # Log long or suspicious search terms
    if sanitized.length > 50 || sanitized.match?(/[<>{}\\[\\]\\\\]/)
      Rails.logger.info "[SEARCH] Long/suspicious search from IP #{request.remote_ip}: #{sanitized[0, 100]}"
    end
    
    sanitized
  end

  # Security: Rate limiting check (implement if using rack-attack gem)
  # def check_search_rate_limit
  #   # This would be implemented with rack-attack or similar
  #   # throttle('search_req/ip', limit: 60, period: 1.minute) do |req|
  #   #   req.ip if req.path == '/businesses' && req.params['search'].present?
  #   # end
  # end
end
