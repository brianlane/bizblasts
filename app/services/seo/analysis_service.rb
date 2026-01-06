# frozen_string_literal: true

module Seo
  # Service for analyzing SEO performance and generating recommendations
  # Includes Google ranking estimation and suggestions based on business details
  class AnalysisService
    attr_reader :business

    # SEO factor weights for overall score calculation
    SCORE_WEIGHTS = {
      title: 15,
      description: 10,
      content: 15,
      local_seo: 20,
      technical: 15,
      images: 10,
      linking: 5,
      mobile: 10
    }.freeze

    # Industry-specific keyword templates
    INDUSTRY_KEYWORDS = {
      hair_salons: ['haircut', 'hair styling', 'hair color', 'salon', 'hairdresser'],
      massage_therapy: ['massage', 'relaxation', 'spa', 'therapeutic massage', 'wellness'],
      auto_repair: ['auto repair', 'mechanic', 'car service', 'brake repair', 'oil change'],
      dental_care: ['dentist', 'dental care', 'teeth cleaning', 'dental office'],
      landscaping: ['landscaping', 'lawn care', 'garden design', 'yard maintenance'],
      cleaning_services: ['cleaning service', 'house cleaning', 'maid service', 'deep cleaning'],
      personal_training: ['personal trainer', 'fitness', 'gym', 'workout', 'exercise'],
      photography: ['photographer', 'photography', 'photo session', 'portrait'],
      plumbing: ['plumber', 'plumbing', 'drain cleaning', 'pipe repair'],
      hvac_services: ['HVAC', 'air conditioning', 'heating', 'AC repair', 'furnace']
    }.freeze

    def initialize(business)
      @business = business
    end

    # Perform complete SEO analysis
    # @return [Hash] Complete analysis results
    def analyze
      {
        overall_score: calculate_overall_score,
        score_breakdown: score_breakdown,
        ranking_potential: estimate_ranking_potential,
        current_rankings: estimate_current_rankings,
        suggestions: generate_suggestions,
        keyword_opportunities: find_keyword_opportunities,
        competitor_analysis: analyze_competitors,
        technical_issues: identify_technical_issues,
        content_analysis: analyze_content,
        local_seo_analysis: analyze_local_seo
      }
    end

    # Calculate overall SEO score (0-100)
    # @return [Integer] SEO score
    def calculate_overall_score
      breakdown = score_breakdown
      
      weighted_sum = breakdown.sum do |factor, score|
        weight = SCORE_WEIGHTS[factor] || 0
        (score * weight / 100.0)
      end
      
      weighted_sum.round
    end

    # Get detailed score breakdown by factor
    # @return [Hash] Scores by factor
    def score_breakdown
      {
        title: analyze_title_score,
        description: analyze_description_score,
        content: analyze_content_score,
        local_seo: analyze_local_seo_score,
        technical: analyze_technical_score,
        images: analyze_image_score,
        linking: analyze_linking_score,
        mobile: analyze_mobile_score
      }
    end

    # Estimate Google ranking potential for target keywords
    # @return [Hash] Ranking potential assessment
    def estimate_ranking_potential
      keywords = generate_target_keywords
      
      keywords.map do |keyword|
        difficulty = estimate_keyword_difficulty(keyword)
        relevance = calculate_keyword_relevance(keyword)
        
        {
          keyword: keyword,
          difficulty: difficulty,
          relevance: relevance,
          estimated_position: estimate_position(difficulty, relevance),
          opportunity_score: calculate_opportunity_score(difficulty, relevance),
          recommendation: position_recommendation(difficulty, relevance)
        }
      end.sort_by { |k| -k[:opportunity_score] }
    end

    # Estimate current rankings based on business profile
    # @return [Hash] Estimated rankings
    def estimate_current_rankings
      keywords = generate_target_keywords.first(10)
      
      rankings = {}
      keywords.each do |keyword|
        position = estimate_current_position(keyword)
        rankings[keyword] = {
          position: position,
          position_label: position_label(position),
          trend: 'stable', # Would be calculated from historical data
          last_checked: Time.current.iso8601,
          improvement_potential: calculate_improvement_potential(position)
        }
      end
      
      rankings
    end

    # Generate actionable SEO suggestions
    # @return [Array<Hash>] Prioritized suggestions
    def generate_suggestions
      suggestions = []
      
      # Title suggestions
      suggestions.concat(title_suggestions)
      
      # Description suggestions
      suggestions.concat(description_suggestions)
      
      # Content suggestions
      suggestions.concat(content_suggestions)
      
      # Local SEO suggestions
      suggestions.concat(local_seo_suggestions)
      
      # Technical suggestions
      suggestions.concat(technical_suggestions)
      
      # Image suggestions
      suggestions.concat(image_suggestions)
      
      # Sort by priority and impact
      suggestions.sort_by { |s| [-priority_value(s[:priority]), -s[:impact]] }
    end

    # Generate target keywords based on business details
    # @return [Array<String>] Target keywords
    def generate_target_keywords
      keywords = []
      city = business.city.presence
      state = business.state.presence

      # Industry + location keywords
      industry_name = business.industry&.to_s&.humanize || 'business'

      keywords << "#{industry_name} near me"
      if city
        keywords << "#{industry_name} in #{city}"
        keywords << "#{city} #{industry_name}"
        keywords << "best #{industry_name} #{city}"
        keywords << "local #{industry_name} #{city}"
        keywords << "affordable #{industry_name} #{city}"
        keywords << "top rated #{industry_name} #{city}"
      end
      keywords << "#{industry_name} #{city} #{state}" if city && state

      # Business name keywords
      keywords << business.name if business.name.present?
      keywords << "#{business.name} #{city}" if business.name.present? && city

      # Service-specific keywords
      business.services.active.limit(10).each do |service|
        keywords << "#{service.name} near me"
        keywords << "#{service.name} #{city}" if city
        keywords << "#{service.name} #{state}" if state
      end

      # Industry-specific keywords
      if INDUSTRY_KEYWORDS[business.industry&.to_sym]
        INDUSTRY_KEYWORDS[business.industry.to_sym].each do |term|
          keywords << "#{term} near me"
          keywords << "#{term} #{city}" if city
        end
      end

      keywords.uniq.first(50)
    end

    # Find keyword opportunities (low competition, high relevance)
    # @return [Array<Hash>] Keyword opportunities
    def find_keyword_opportunities
      all_keywords = generate_target_keywords
      
      opportunities = all_keywords.map do |keyword|
        difficulty = estimate_keyword_difficulty(keyword)
        relevance = calculate_keyword_relevance(keyword)
        search_volume = estimate_search_volume(keyword)
        
        {
          keyword: keyword,
          difficulty: difficulty,
          relevance: relevance,
          estimated_search_volume: search_volume,
          opportunity_score: calculate_opportunity_score(difficulty, relevance),
          quick_win: difficulty < 40 && relevance > 70
        }
      end
      
      opportunities
        .select { |o| o[:opportunity_score] > 50 }
        .sort_by { |o| -o[:opportunity_score] }
        .first(20)
    end

    private

    # ==================== Score Analysis Methods ====================

    def analyze_title_score
      score = 50 # Base score
      
      # Check if business name is present
      score += 15 if business.name.present?
      
      # Check if meta title would include city
      score += 15 if business.city.present?
      
      # Check title length (ideal: 50-60 chars)
      title_length = "#{business.name} | #{business.industry&.humanize} in #{business.city}".length
      score += 10 if title_length.between?(40, 65)
      
      # Check for industry keyword
      score += 10 if business.industry.present?
      
      [score, 100].min
    end

    def analyze_description_score
      score = 30 # Base score
      
      # Check if description exists
      if business.description.present?
        score += 20
        
        # Length check (ideal: 150-160 chars)
        if business.description.length.between?(100, 200)
          score += 20
        elsif business.description.length > 50
          score += 10
        end
        
        # Check for location mention
        score += 15 if business.description.downcase.include?(business.city.to_s.downcase)
        
        # Check for call to action
        cta_words = %w[call book schedule contact visit]
        score += 15 if cta_words.any? { |w| business.description.downcase.include?(w) }
      end
      
      [score, 100].min
    end

    def analyze_content_score
      score = 40 # Base score
      
      # Check for service descriptions
      services_with_descriptions = business.services.where.not(description: [nil, '']).count
      if services_with_descriptions > 0
        score += [services_with_descriptions * 5, 20].min
      end
      
      # Check for pages
      published_pages = business.pages.published.count
      score += [published_pages * 5, 20].min
      
      # Check for rich content (blog posts, FAQs)
      # This could be expanded based on actual content features
      score += 10 if business.description.to_s.length > 200
      
      # Check for unique content
      score += 10 if business.services.count > 3
      
      [score, 100].min
    end

    def analyze_local_seo_score
      score = 20 # Base score
      
      # Address completeness
      score += 10 if business.address.present?
      score += 10 if business.city.present?
      score += 10 if business.state.present?
      score += 5 if business.zip.present?
      
      # Phone number
      score += 10 if business.phone.present?
      
      # Business hours
      score += 10 if business.hours.present? && business.hours.any?
      
      # Email
      score += 5 if business.email.present?
      
      # Google Place ID (indicates Google Business Profile)
      score += 20 if business.google_place_id.present?
      
      [score, 100].min
    end

    def analyze_technical_score
      score = 60 # Base score (assuming SSL and responsive design)
      
      # Custom domain bonus
      score += 15 if business.host_type_custom_domain?
      
      # Active status
      score += 10 if business.active?
      
      # Pages configured
      score += 15 if business.pages.published.exists?
      
      [score, 100].min
    end

    def analyze_image_score
      score = 30 # Base score
      
      # Logo present
      score += 25 if business.logo.attached?
      
      # Gallery photos
      # Only count business-owned photos, not section-owned photos
      gallery_count = business.gallery_photos.business_owned.count
      score += [gallery_count * 5, 25].min if gallery_count > 0
      
      # Gallery video (bonus)
      score += 20 if business.gallery_video.attached?
      
      [score, 100].min
    end

    def analyze_linking_score
      score = 40 # Base score
      
      # Internal pages
      page_count = business.pages.published.count
      score += [page_count * 10, 30].min
      
      # Services linked
      score += 15 if business.services.active.count > 0
      
      # Products linked
      score += 15 if business.products.active.count > 0
      
      [score, 100].min
    end

    def analyze_mobile_score
      # Assuming responsive design is in place
      # Could be enhanced with actual mobile testing
      80
    end

    # ==================== Keyword Analysis Methods ====================

    def estimate_keyword_difficulty(keyword)
      # Simplified keyword difficulty estimation
      # In production, this could use external API data

      difficulty = 50 # Base difficulty

      # Location-specific keywords are generally easier (guard against empty string matching everything)
      difficulty -= 15 if business.city.present? && keyword.include?(business.city)
      difficulty -= 10 if keyword.include?('near me')
      
      # Long-tail keywords are easier
      word_count = keyword.split.length
      difficulty -= (word_count - 2) * 5 if word_count > 2
      
      # High-competition terms
      high_comp_terms = %w[best top cheap affordable professional]
      difficulty += 10 if high_comp_terms.any? { |t| keyword.include?(t) }
      
      # Industry competition (simplified)
      high_comp_industries = %w[legal dental medical]
      difficulty += 15 if high_comp_industries.any? { |i| keyword.include?(i) }
      
      [[difficulty, 10].max, 100].min
    end

    def calculate_keyword_relevance(keyword)
      relevance = 50 # Base relevance
      keyword_lower = keyword.downcase

      # Business name match (guard against empty string which would match everything)
      business_name_first_word = business.name.to_s.downcase.split.first
      relevance += 20 if business_name_first_word.present? && keyword_lower.include?(business_name_first_word)

      # Location match (guard against empty string)
      city_lower = business.city.to_s.downcase
      relevance += 15 if city_lower.present? && keyword_lower.include?(city_lower)

      # Industry match (guard against empty string)
      industry_name = business.industry&.to_s&.gsub('_', ' ')&.downcase
      relevance += 15 if industry_name.present? && keyword_lower.include?(industry_name)

      # Service match (guard against nil/empty strings)
      service_names = business.services.pluck(:name).compact.map(&:downcase)
      relevance += 10 if service_names.any? do |service_name|
        first_word = service_name.split.first
        first_word.present? && keyword_lower.include?(first_word)
      end

      [[relevance, 0].max, 100].min
    end

    def estimate_search_volume(keyword)
      # Simplified search volume estimation
      # In production, use Google Keyword Planner API

      volume = 100 # Base volume

      # City population factor (simplified, guard against empty string matching everything)
      volume *= 2 if business.city.present? && keyword.include?(business.city)
      
      # "near me" searches are common
      volume *= 3 if keyword.include?('near me')
      
      # Industry-specific modifiers
      if business.industry&.to_sym.in?([:hair_salons, :auto_repair, :restaurants])
        volume *= 2
      end
      
      volume.round
    end

    def estimate_position(difficulty, relevance)
      # Estimate ranking position based on difficulty and relevance
      # Lower score = better position
      
      base_position = 50
      
      # High relevance improves position
      base_position -= (relevance - 50) * 0.3
      
      # High difficulty worsens position
      base_position += (difficulty - 50) * 0.4
      
      # Business age factor (simplified - newer businesses rank lower)
      days_active = (Time.current - business.created_at).to_i / 86400
      base_position -= [days_active / 30, 10].min
      
      # Custom domain bonus
      base_position -= 5 if business.host_type_custom_domain?
      
      # Clamp to reasonable range
      [[base_position.round, 1].max, 100].min
    end

    def estimate_current_position(keyword)
      difficulty = estimate_keyword_difficulty(keyword)
      relevance = calculate_keyword_relevance(keyword)
      estimate_position(difficulty, relevance)
    end

    def position_label(position)
      case position
      when 1..3 then 'Top 3'
      when 4..10 then 'Page 1'
      when 11..20 then 'Page 2'
      when 21..50 then 'Pages 3-5'
      else 'Beyond Page 5'
      end
    end

    def calculate_opportunity_score(difficulty, relevance)
      # Higher score = better opportunity
      # Prefer low difficulty + high relevance
      
      difficulty_factor = (100 - difficulty) / 100.0
      relevance_factor = relevance / 100.0
      
      ((difficulty_factor * 0.4 + relevance_factor * 0.6) * 100).round
    end

    def calculate_improvement_potential(position)
      case position
      when 1..3 then 'Maintain position'
      when 4..10 then 'High - can reach top 3'
      when 11..20 then 'Medium - can reach page 1'
      when 21..50 then 'Good - with consistent effort'
      else 'Requires significant work'
      end
    end

    def position_recommendation(difficulty, relevance)
      if difficulty < 40 && relevance > 70
        'Quick Win - Prioritize this keyword'
      elsif difficulty < 60 && relevance > 60
        'Good Target - Include in content strategy'
      elsif relevance > 80
        'High Relevance - Worth the effort despite competition'
      else
        'Consider - Monitor for opportunities'
      end
    end

    # ==================== Suggestion Generation Methods ====================

    def title_suggestions
      suggestions = []
      
      unless business.city.present?
        suggestions << {
          priority: 'high',
          category: 'title',
          title: 'Add city to business profile',
          suggestion: 'Include your city name in your business profile to improve local search rankings.',
          impact: 15,
          effort: 'low'
        }
      end
      
      unless business.industry.present?
        suggestions << {
          priority: 'high',
          category: 'title',
          title: 'Set business industry',
          suggestion: 'Select your business industry to help search engines understand your services.',
          impact: 12,
          effort: 'low'
        }
      end
      
      suggestions
    end

    def description_suggestions
      suggestions = []
      
      if business.description.blank?
        suggestions << {
          priority: 'high',
          category: 'description',
          title: 'Add business description',
          suggestion: 'Write a compelling 150-160 character description that includes your services and location.',
          impact: 20,
          effort: 'low'
        }
      elsif business.description.length < 100
        suggestions << {
          priority: 'medium',
          category: 'description',
          title: 'Expand business description',
          suggestion: 'Your description is too short. Aim for 150-160 characters for optimal SEO.',
          impact: 10,
          effort: 'low'
        }
      end
      
      if business.description.present? && !business.description.downcase.include?(business.city.to_s.downcase)
        suggestions << {
          priority: 'medium',
          category: 'description',
          title: 'Add location to description',
          suggestion: "Mention #{business.city} in your business description to improve local search visibility.",
          impact: 8,
          effort: 'low'
        }
      end
      
      suggestions
    end

    def content_suggestions
      suggestions = []
      
      if business.services.active.count < 3
        suggestions << {
          priority: 'medium',
          category: 'content',
          title: 'Add more services',
          suggestion: 'Add detailed service pages to give search engines more content to index.',
          impact: 15,
          effort: 'medium'
        }
      end
      
      services_without_desc = business.services.active.where(description: [nil, '']).count
      if services_without_desc > 0
        suggestions << {
          priority: 'medium',
          category: 'content',
          title: 'Add service descriptions',
          suggestion: "#{services_without_desc} services lack descriptions. Add unique descriptions of 100+ words each.",
          impact: 12,
          effort: 'medium'
        }
      end
      
      if business.pages.published.count < 3
        suggestions << {
          priority: 'low',
          category: 'content',
          title: 'Create additional pages',
          suggestion: 'Add About, Services, and FAQ pages to provide more content for search engines.',
          impact: 10,
          effort: 'medium'
        }
      end
      
      suggestions
    end

    def local_seo_suggestions
      suggestions = []
      
      unless business.google_place_id.present?
        suggestions << {
          priority: 'high',
          category: 'local',
          title: 'Claim Google Business Profile',
          suggestion: 'Create and verify your Google Business Profile to appear in Google Maps and local search results.',
          impact: 25,
          effort: 'medium'
        }
      end
      
      if business.hours.blank? || business.hours.empty?
        suggestions << {
          priority: 'medium',
          category: 'local',
          title: 'Add business hours',
          suggestion: 'Set your business hours to help customers and improve local search visibility.',
          impact: 10,
          effort: 'low'
        }
      end
      
      unless business.phone.present?
        suggestions << {
          priority: 'high',
          category: 'local',
          title: 'Add phone number',
          suggestion: 'Add a phone number for click-to-call functionality and improved local SEO.',
          impact: 12,
          effort: 'low'
        }
      end
      
      suggestions
    end

    def technical_suggestions
      suggestions = []
      
      if business.host_type_subdomain?
        suggestions << {
          priority: 'low',
          category: 'technical',
          title: 'Consider a custom domain',
          suggestion: 'A custom domain can improve brand recognition and may have slight SEO benefits.',
          impact: 8,
          effort: 'medium'
        }
      end
      
      suggestions
    end

    def image_suggestions
      suggestions = []
      
      unless business.logo.attached?
        suggestions << {
          priority: 'medium',
          category: 'images',
          title: 'Add business logo',
          suggestion: 'Upload a logo to improve brand recognition and social sharing appearance.',
          impact: 10,
          effort: 'low'
        }
      end
      
      # Only count business-owned photos, not section-owned photos
      if business.gallery_photos.business_owned.count < 5
        suggestions << {
          priority: 'medium',
          category: 'images',
          title: 'Add more gallery photos',
          suggestion: 'Add high-quality photos of your work, team, or location. Images improve engagement and SEO.',
          impact: 8,
          effort: 'medium'
        }
      end
      
      suggestions
    end

    def priority_value(priority)
      case priority
      when 'high' then 3
      when 'medium' then 2
      when 'low' then 1
      else 0
      end
    end

    # ==================== Competitor Analysis ====================

    def analyze_competitors
      # Simplified competitor analysis
      # In production, this could scrape or use API data
      
      {
        industry_benchmark: {
          avg_services: 8,
          avg_reviews: 25,
          custom_domain_rate: 60,
          avg_seo_score: 65
        },
        your_performance: {
          services: business.services.active.count,
          reviews: 0, # Would need review system
          custom_domain: business.host_type_custom_domain?,
          seo_score: calculate_overall_score
        },
        gaps: identify_competitive_gaps
      }
    end

    def identify_competitive_gaps
      gaps = []
      
      if business.services.active.count < 5
        gaps << 'Below average number of services'
      end
      
      unless business.host_type_custom_domain?
        gaps << 'No custom domain (60% of competitors have one)'
      end
      
      unless business.google_place_id.present?
        gaps << 'Missing Google Business Profile'
      end
      
      if calculate_overall_score < 65
        gaps << 'SEO score below industry average'
      end
      
      gaps
    end

    def identify_technical_issues
      issues = []
      
      # Check for missing essential elements
      issues << { issue: 'Missing business description', severity: 'high' } if business.description.blank?
      issues << { issue: 'Missing business hours', severity: 'medium' } if business.hours.blank?
      issues << { issue: 'Missing phone number', severity: 'medium' } unless business.phone.present?
      issues << { issue: 'Missing business logo', severity: 'low' } unless business.logo.attached?
      
      issues
    end

    def analyze_content
      {
        total_pages: business.pages.count,
        published_pages: business.pages.published.count,
        services_with_descriptions: business.services.where.not(description: [nil, '']).count,
        total_services: business.services.active.count,
        avg_description_length: calculate_avg_description_length,
        content_freshness: business.updated_at
      }
    end

    def calculate_avg_description_length
      descriptions = business.services.pluck(:description).compact.reject(&:blank?)
      return 0 if descriptions.empty?
      
      (descriptions.map(&:length).sum / descriptions.size.to_f).round
    end

    def analyze_local_seo
      {
        address_complete: business.address.present? && business.city.present? && business.state.present?,
        phone_present: business.phone.present?,
        hours_set: business.hours.present? && business.hours.any?,
        google_profile_linked: business.google_place_id.present?,
        local_keywords_in_content: check_local_keywords_in_content
      }
    end

    def check_local_keywords_in_content
      return false unless business.city.present?
      
      city_lower = business.city.downcase
      
      # Check if city appears in description or service names
      business.description.to_s.downcase.include?(city_lower) ||
        business.services.any? { |s| s.name.to_s.downcase.include?(city_lower) }
    end
  end
end

