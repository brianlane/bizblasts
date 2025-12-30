# frozen_string_literal: true

module BusinessManager
  class AnalyticsController < BusinessManager::BaseController
    before_action :set_analytics_services
    
    # GET /manage/analytics
    def index
      @period = params[:period]&.to_sym || :last_30_days
      @tab = params[:tab] || 'overview'
      
      @overview = @dashboard_service.overview_metrics(period: @period)
      @quick_stats = @dashboard_service.quick_stats
      @comparison = @dashboard_service.period_comparison(period: @period)
    end

    # GET /manage/analytics/traffic
    def traffic
      @period = params[:period]&.to_sym || :last_30_days
      
      @overview = @dashboard_service.overview_metrics(period: @period)
      @traffic_sources = @overview[:traffic_sources]
      @top_pages = @overview[:top_pages]
      @trend_data = @overview[:trend]
    end

    # GET /manage/analytics/conversions
    def conversions
      @period = params[:period]&.to_sym || :last_30_days

      @conversion_service = ::Analytics::ConversionAttributionService.new(@current_business)
      
      @conversion_rates = @conversion_service.conversion_rates_by_source(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @top_converting_pages = @conversion_service.top_converting_pages(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @funnel = @conversion_service.funnel_analysis(
        'booking',
        start_date: period_start(@period),
        end_date: Time.current
      )
    end

    # GET /manage/analytics/bookings
    def bookings
      @period = params[:period]&.to_sym || :last_30_days

      @booking_service = ::Analytics::BookingAnalyticsService.new(@current_business)
      
      @metrics = @booking_service.metrics(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @top_services = @booking_service.top_services(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @staff_performance = @booking_service.staff_performance(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @heatmap = @booking_service.booking_heatmap(
        start_date: period_start(@period),
        end_date: Time.current
      )
    end

    # GET /manage/analytics/products
    def products
      @period = params[:period]&.to_sym || :last_30_days

      @product_service = ::Analytics::ProductAnalyticsService.new(@current_business)
      
      @metrics = @product_service.metrics(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @top_products = @product_service.top_products(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @cart_abandonment = @product_service.cart_abandonment(
        start_date: period_start(@period),
        end_date: Time.current
      )
    end

    # GET /manage/analytics/services
    def services
      @period = params[:period]&.to_sym || :last_30_days

      @service_analytics = ::Analytics::ServiceAnalyticsService.new(@current_business)
      
      @metrics = @service_analytics.metrics(
        start_date: period_start(@period),
        end_date: Time.current
      )
      
      @view_booking_gap = @service_analytics.calculate_view_booking_gap(
        period_start(@period),
        Time.current
      )
      
      @service_comparison = @service_analytics.service_comparison(
        start_date: period_start(@period),
        end_date: Time.current
      )
    end

    # GET /manage/analytics/seo
    def seo
      @seo_service = Seo::AnalysisService.new(@current_business)
      @analysis = @seo_service.analyze
      
      @seo_config = @current_business.seo_configuration || 
                    @current_business.build_seo_configuration
      
      @structured_data_service = Seo::StructuredDataService.new(@current_business)
      @local_business_schema = @structured_data_service.local_business_schema
    end

    # GET /manage/analytics/realtime
    def realtime
      @realtime = @dashboard_service.realtime_metrics

      respond_to do |format|
        format.html
        format.json { render json: @realtime }
      end
    end

    # GET /manage/analytics/export
    def export
      @export_types = ::Analytics::ExportService.available_export_types
      @period = params[:period]&.to_sym || :last_30_days
    end

    # POST /manage/analytics/export
    def perform_export
      export_service = ::Analytics::ExportService.new(@current_business)

      export_type = params[:export_type]&.to_sym
      format = params[:format_type] || 'csv'
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current

      result = export_service.export(
        type: export_type,
        start_date: start_date,
        end_date: end_date,
        format: format
      )

      send_data result[:data],
                filename: result[:filename],
                type: result[:content_type],
                disposition: 'attachment'
    rescue ArgumentError => e
      redirect_to business_manager_export_analytics_path, alert: e.message
    rescue StandardError => e
      Rails.logger.error "[AnalyticsExport] Error: #{e.message}"
      redirect_to business_manager_export_analytics_path, alert: 'An error occurred while generating the export.'
    end

    private

    def set_analytics_services
      @dashboard_service = ::Analytics::DashboardService.new(@current_business)
    end

    def period_start(period)
      case period
      when :today then Time.current.beginning_of_day
      when :last_7_days then 7.days.ago
      when :last_30_days then 30.days.ago
      when :last_90_days then 90.days.ago
      else 30.days.ago
      end
    end
  end
end

