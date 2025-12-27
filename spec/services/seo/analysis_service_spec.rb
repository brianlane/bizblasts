# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Seo::AnalysisService, type: :service do
  let(:business) do
    create(:business,
           name: 'Test Salon',
           industry: 'hair_salons',
           city: 'Portland',
           state: 'OR',
           address: '123 Main St',
           phone: '555-123-4567',
           description: 'Best hair salon in Portland, OR. Professional stylists and great service.')
  end
  
  let(:service) { described_class.new(business) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '#analyze' do
    it 'returns complete analysis results' do
      analysis = service.analyze
      
      expect(analysis).to have_key(:overall_score)
      expect(analysis).to have_key(:score_breakdown)
      expect(analysis).to have_key(:ranking_potential)
      expect(analysis).to have_key(:current_rankings)
      expect(analysis).to have_key(:suggestions)
      expect(analysis).to have_key(:keyword_opportunities)
    end
  end

  describe '#calculate_overall_score' do
    it 'returns a score between 0 and 100' do
      score = service.calculate_overall_score
      
      expect(score).to be >= 0
      expect(score).to be <= 100
    end

    it 'gives higher score to complete business profiles' do
      # Complete business
      score_complete = service.calculate_overall_score
      
      # Incomplete business
      incomplete_business = create(:business, name: 'Test', description: nil, phone: nil)
      incomplete_service = described_class.new(incomplete_business)
      score_incomplete = incomplete_service.calculate_overall_score
      
      expect(score_complete).to be > score_incomplete
    end
  end

  describe '#score_breakdown' do
    it 'returns scores for all SEO factors' do
      breakdown = service.score_breakdown
      
      expect(breakdown).to have_key(:title)
      expect(breakdown).to have_key(:description)
      expect(breakdown).to have_key(:content)
      expect(breakdown).to have_key(:local_seo)
      expect(breakdown).to have_key(:technical)
      expect(breakdown).to have_key(:images)
      expect(breakdown).to have_key(:linking)
      expect(breakdown).to have_key(:mobile)
    end

    it 'returns scores between 0 and 100' do
      breakdown = service.score_breakdown
      
      breakdown.each do |factor, score|
        expect(score).to be >= 0
        expect(score).to be <= 100
      end
    end
  end

  describe '#generate_target_keywords' do
    it 'generates industry-specific keywords' do
      keywords = service.generate_target_keywords.map(&:downcase)
      
      expect(keywords).to include('hair salons in portland')
      expect(keywords).to include('portland hair salons')
    end

    it 'generates location-based keywords' do
      keywords = service.generate_target_keywords
      
      keywords_with_city = keywords.select { |k| k.include?('Portland') }
      expect(keywords_with_city).not_to be_empty
    end

    it 'includes business name' do
      keywords = service.generate_target_keywords
      
      expect(keywords).to include(business.name)
    end

    it 'generates service-specific keywords' do
      create(:service, business: business, name: 'Haircut', active: true)
      
      keywords = service.generate_target_keywords
      
      expect(keywords).to include('Haircut Portland')
    end
  end

  describe '#generate_suggestions' do
    it 'returns prioritized suggestions' do
      suggestions = service.generate_suggestions
      
      expect(suggestions).to be_an(Array)
      
      if suggestions.any?
        first_suggestion = suggestions.first
        expect(first_suggestion).to have_key(:priority)
        expect(first_suggestion).to have_key(:category)
        expect(first_suggestion).to have_key(:suggestion)
        expect(first_suggestion).to have_key(:impact)
      end
    end

    it 'sorts by priority and impact' do
      suggestions = service.generate_suggestions
      
      return if suggestions.length < 2
      
      priorities = suggestions.map { |s| s[:priority] }
      high_indices = priorities.each_index.select { |i| priorities[i] == 'high' }
      low_indices = priorities.each_index.select { |i| priorities[i] == 'low' }
      
      # High priority should come before low priority
      if high_indices.any? && low_indices.any?
        expect(high_indices.max).to be < low_indices.min
      end
    end
  end

  describe '#estimate_ranking_potential' do
    it 'returns keyword analysis with position estimates' do
      potential = service.estimate_ranking_potential
      
      expect(potential).to be_an(Array)
      
      if potential.any?
        keyword_data = potential.first
        expect(keyword_data).to have_key(:keyword)
        expect(keyword_data).to have_key(:difficulty)
        expect(keyword_data).to have_key(:relevance)
        expect(keyword_data).to have_key(:estimated_position)
        expect(keyword_data).to have_key(:opportunity_score)
      end
    end

    it 'sorts by opportunity score' do
      potential = service.estimate_ranking_potential
      
      return if potential.length < 2
      
      scores = potential.map { |p| p[:opportunity_score] }
      expect(scores).to eq(scores.sort.reverse)
    end
  end

  describe '#find_keyword_opportunities' do
    it 'identifies quick win keywords' do
      opportunities = service.find_keyword_opportunities
      
      quick_wins = opportunities.select { |o| o[:quick_win] }
      
      quick_wins.each do |opportunity|
        expect(opportunity[:difficulty]).to be < 40
        expect(opportunity[:relevance]).to be > 70
      end
    end
  end
end

