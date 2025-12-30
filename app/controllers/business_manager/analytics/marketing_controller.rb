# frozen_string_literal: true

module BusinessManager
  module Analytics
    # Controller for marketing performance and campaign ROI analytics
    class MarketingController < BusinessManager::BaseController
      before_action :set_marketing_service

      def index
        @period = params[:period]&.to_sym || :last_30_days
        period_days = period_to_days(@period)

        @spend_efficiency = @marketing_service.marketing_spend_efficiency(period_days)
        @campaigns_summary = @marketing_service.campaigns_summary(period_days).first(10)
        @acquisition_sources = @marketing_service.acquisition_by_source(period_days)
        @channel_performance = @marketing_service.channel_performance(period_days)
        @promotions_summary = @marketing_service.promotions_summary(period_days).first(5)

        # Set @marketing_summary for view compatibility
        avg_conversion_rate = if @campaigns_summary.any?
                               @campaigns_summary.sum { |c| c[:conversion_rate] } / @campaigns_summary.size
                             else
                               0.0
                             end

        @marketing_summary = @spend_efficiency.merge(
          avg_roi: @spend_efficiency[:roi],
          conversion_rate: avg_conversion_rate
        )
      end

      def campaigns
        period = params[:period]&.to_i&.days || 30.days
        @campaigns_data = @marketing_service.campaigns_summary(period)

        respond_to do |format|
          format.json { render json: @campaigns_data }
          format.html
        end
      end

      def campaign_roi
        campaign_id = params[:id]
        period = params[:period]&.to_i&.days

        @campaign_data = @marketing_service.campaign_roi(campaign_id, period)

        respond_to do |format|
          format.json { render json: @campaign_data }
          format.html
        end
      end

      def email_campaigns
        period = params[:period]&.to_i&.days || 30.days
        @email_data = @marketing_service.email_campaign_performance(period)

        respond_to do |format|
          format.json { render json: @email_data }
          format.html
        end
      end

      def sms_campaigns
        period = params[:period]&.to_i&.days || 30.days
        @sms_data = @marketing_service.sms_campaign_performance(period)

        respond_to do |format|
          format.json { render json: @sms_data }
          format.html
        end
      end

      def promotions
        period = params[:period]&.to_i&.days || 30.days
        @promotions_data = @marketing_service.promotions_summary(period)

        respond_to do |format|
          format.json { render json: @promotions_data }
          format.html
        end
      end

      def promotion_effectiveness
        promotion_id = params[:id]
        @promotion_data = @marketing_service.promotion_effectiveness(promotion_id)

        respond_to do |format|
          format.json { render json: @promotion_data }
          format.html
        end
      end

      def referrals
        period = params[:period]&.to_i&.days || 30.days
        @referral_data = @marketing_service.referral_program_metrics(period)

        respond_to do |format|
          format.json { render json: @referral_data }
          format.html
        end
      end

      def acquisition
        period = params[:period]&.to_i&.days || 30.days
        @acquisition_data = @marketing_service.acquisition_by_source(period)

        respond_to do |format|
          format.json { render json: @acquisition_data }
          format.html
        end
      end

      def channels
        period = params[:period]&.to_i&.days || 30.days
        @channel_data = @marketing_service.channel_performance(period)

        respond_to do |format|
          format.json { render json: @channel_data }
          format.html
        end
      end

      def attribution
        period = params[:period]&.to_i&.days || 30.days
        @attribution_data = @marketing_service.attribution_analysis(period)

        respond_to do |format|
          format.json { render json: @attribution_data }
          format.html
        end
      end

      def spend_efficiency
        period = params[:period]&.to_i&.days || 30.days
        @efficiency_data = @marketing_service.marketing_spend_efficiency(period)

        respond_to do |format|
          format.json { render json: @efficiency_data }
          format.html
        end
      end

      def export
        period = params[:period]&.to_i&.days || 30.days

        csv_data = CSV.generate do |csv|
          csv << ['Marketing Performance Export']
          csv << []

          # Marketing spend efficiency
          efficiency = @marketing_service.marketing_spend_efficiency(period)
          csv << ['Marketing Spend Efficiency']
          csv << ['Total Spend', efficiency[:total_spend]]
          csv << ['Total Revenue', efficiency[:total_revenue]]
          csv << ['Total Conversions', efficiency[:total_conversions]]
          csv << ['Cost per Conversion', efficiency[:cost_per_conversion]]
          csv << ['ROAS', efficiency[:roas]]
          csv << ['ROI', "#{efficiency[:roi]}%"]
          csv << []

          # Campaigns summary
          csv << ['Top Campaigns by ROI']
          csv << ['Campaign', 'Revenue', 'Cost', 'ROI', 'Conversions', 'Conversion Rate']
          @marketing_service.campaigns_summary(period).first(10).each do |campaign|
            csv << [
              campaign[:campaign_name],
              campaign[:revenue],
              campaign[:cost],
              "#{campaign[:roi]}%",
              campaign[:conversions],
              "#{campaign[:conversion_rate]}%"
            ]
          end
          csv << []

          # Acquisition by source
          csv << ['Customer Acquisition by Source']
          csv << ['Source', 'Acquisitions', 'Percentage', 'Cost per Acquisition']
          @marketing_service.acquisition_by_source(period).each do |source|
            csv << [
              source[:source],
              source[:acquisitions],
              "#{source[:percentage]}%",
              source[:cost_per_acquisition]
            ]
          end
        end

        send_data csv_data,
                  filename: "marketing-analytics-#{Date.current}.csv",
                  type: 'text/csv',
                  disposition: 'attachment'
      end

      private

      def set_marketing_service
        @marketing_service = ::Analytics::MarketingPerformanceService.new(business)
      end

      def business
        current_business
      end

      def period_to_days(period)
        case period
        when :today then 1.day
        when :last_7_days then 7.days
        when :last_30_days then 30.days
        when :last_90_days then 90.days
        else 30.days
        end
      end
    end
  end
end
