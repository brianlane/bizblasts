# frozen_string_literal: true

module Analytics
  # Job for updating SEO analysis and scores for businesses
  # Runs daily at 3 AM to update SEO configurations
  class SeoAnalysisJob < ApplicationJob
    queue_as :analytics

    def perform(business_id = nil)
      if business_id.present?
        # Process single business
        business = Business.find_by(id: business_id)
        return unless business
        
        analyze_business(business)
      else
        # Process all active businesses
        Rails.logger.info "[SeoAnalysis] Starting SEO analysis for all businesses..."
        
        Business.active.find_each do |business|
          analyze_business(business)
        rescue StandardError => e
          Rails.logger.error "[SeoAnalysis] Error analyzing business #{business.id}: #{e.message}"
        end
        
        Rails.logger.info "[SeoAnalysis] SEO analysis complete"
      end
    end

    private

    def analyze_business(business)
      ActsAsTenant.with_tenant(business) do
        seo_service = Seo::AnalysisService.new(business)
        analysis = seo_service.analyze
        
        # Get or create SEO configuration
        seo_config = business.seo_configuration || business.build_seo_configuration
        
        # Update with analysis results
        seo_config.update!(
          seo_score: analysis[:overall_score],
          seo_score_breakdown: analysis[:score_breakdown],
          seo_suggestions: analysis[:suggestions],
          keyword_rankings: analysis[:current_rankings],
          auto_keywords: seo_service.generate_target_keywords,
          local_business_schema: Seo::StructuredDataService.new(business).local_business_schema,
          last_analysis_at: Time.current
        )
        
        Rails.logger.info "[SeoAnalysis] Updated SEO config for business #{business.id} (score: #{analysis[:overall_score]})"
      end
    end
  end
end

