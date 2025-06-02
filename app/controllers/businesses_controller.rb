# frozen_string_literal: true

# Controller to handle the public listing of businesses
class BusinessesController < ApplicationController
  # Skip user authentication for the index page
  skip_before_action :authenticate_user!, only: [:index]
  # No tenant context needed for the global business list
  # skip_before_action :set_tenant # Assuming set_tenant is not a global filter

  # GET /businesses
  def index
    # Get distinct, human-readable industries for filtering dropdown from enum values
    @industries = Business.industries.values.sort

    # Base query for active businesses
    businesses_query = Business.active

    # Apply industry filter if present
    if params[:industry].present?
      businesses_query = businesses_query.where(industry: params[:industry])
    end

    # Apply sorting
    sort_column = case params[:sort]
                  when 'name' then :name
                  when 'date' then :created_at
                  else :name # Default sort
                  end
    sort_direction = params[:direction] == 'desc' ? :desc : :asc
    businesses_query = businesses_query.order(sort_column => sort_direction)

    # Paginate results (assuming Pagy or Kaminari)
    # Ensure PAGINATION_GEM is set in environment or replace with actual gem name
    # pagination_gem = ENV.fetch('PAGINATION_GEM', 'pagy') # Default to pagy
    # if pagination_gem == 'pagy'
    #   @pagy, @businesses = pagy(businesses_query)
    # else
    #   @businesses = businesses_query.page(params[:page])
    # end
    
    # Using .page for now, assuming Kaminari or similar AR integration
    @businesses = businesses_query.page(params[:page])
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
end
