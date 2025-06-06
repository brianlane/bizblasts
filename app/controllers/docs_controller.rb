# frozen_string_literal: true

# DocsController handles the documentation section
class DocsController < ApplicationController
  # Skip authentication for docs pages
  skip_before_action :authenticate_user!, only: [:index, :show]
  # Skip tenant setting for docs since it's on the main domain
  skip_before_action :set_tenant, only: [:index, :show]

  # Available documentation articles
  DOCS = {
    'business-start-guide' => {
      title: 'Getting Started on BizBlasts',
      description: 'Complete guide to setting up your business profile and taking your first bookings',
      category: 'Getting Started',
      estimated_read_time: '8 min read'
    },
    'legal-setup-arizona' => {
      title: 'Starting a Business in Arizona',
      description: 'Legal requirements, licensing, and tax considerations for starting as an Arizona entrepreneur',
      category: 'Legal & Compliance',
      estimated_read_time: '12 min read'
    },
    'business-growth-strategies' => {
      title: 'Growth Strategies for Businesses',
      description: 'Proven tactics for marketing, customer retention, and scaling your very first business',
      category: 'Business Growth',
      estimated_read_time: '10 min read'
    }
  }.freeze

  def index
    @docs = DOCS
  end

  def show
    # Validate that the doc_id is in our allowed list to prevent path traversal attacks
    @doc_id = validate_doc_id(params[:doc_id])
    
    unless @doc_id
      redirect_to docs_path, alert: 'Documentation not found'
      return
    end
    
    @doc = DOCS[@doc_id]

    @doc_keys = DOCS.keys
    @current_index = @doc_keys.index(@doc_id)
    @previous_doc = @current_index > 0 ? @doc_keys[@current_index - 1] : nil
    @next_doc = @current_index < @doc_keys.length - 1 ? @doc_keys[@current_index + 1] : nil
  end

  private

  # Validates the doc_id parameter against allowed values
  # Returns the validated doc_id or nil if invalid
  def validate_doc_id(doc_id)
    case doc_id
    when 'business-start-guide'
      'business-start-guide'
    when 'legal-setup-arizona'
      'legal-setup-arizona'
    when 'business-growth-strategies'
      'business-growth-strategies'
    else
      nil
    end
  end
end 