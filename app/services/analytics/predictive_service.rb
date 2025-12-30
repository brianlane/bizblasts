# frozen_string_literal: true

module Analytics
  # Facade service for predictive analytics
  # Delegates to specialized services for each prediction type
  # This maintains backward compatibility while improving code organization
  #
  # @example
  #   service = Analytics::PredictiveService.new(business)
  #   forecast = service.forecast_service_demand(service_id)
  #   pricing = service.optimal_pricing_recommendations(service_id)
  class PredictiveService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Demand forecasting - delegates to DemandForecastService
    # @param service_id [Integer] The service to forecast
    # @param days_ahead [Integer] Number of days to forecast (default: 30)
    # @return [Hash] Forecast data or error hash
    def forecast_service_demand(service_id, days_ahead = 30)
      demand_forecast_service.forecast_service_demand(service_id, days_ahead)
    end

    # Pricing recommendations - delegates to PricingOptimizationService
    # @param service_id [Integer] The service to analyze
    # @return [Hash] Pricing recommendations or error hash
    def optimal_pricing_recommendations(service_id)
      pricing_optimization_service.optimal_pricing_recommendations(service_id)
    end

    # Anomaly detection - delegates to AnomalyDetectionService
    # @param metric_type [Symbol] Type of metric (:bookings, :revenue, :inventory)
    # @param period [ActiveSupport::Duration] Time period to analyze (default: 30 days)
    # @return [Array<Hash>] Array of detected anomalies
    def detect_anomalies(metric_type, period = 30.days)
      anomaly_detection_service.detect_anomalies(metric_type, period)
    end

    # Customer next purchase prediction - delegates to CustomerBehaviorService
    # @param customer [TenantCustomer] Customer to analyze
    # @return [Hash, nil] Prediction hash or nil if insufficient data
    def predict_next_purchase(customer)
      customer_behavior_service.predict_next_purchase(customer)
    end

    # Staff scheduling optimization - delegates to StaffSchedulingService
    # @param date [Date] Date to optimize for (default: today)
    # @return [Hash] Scheduling recommendations
    def optimize_staff_scheduling(date = Date.current)
      staff_scheduling_service.optimize_staff_scheduling(date)
    end

    # Inventory restock prediction - delegates to RestockPredictionService
    # @param days_ahead [Integer] Forecast period in days (default: 30)
    # @return [Array<Hash>] Array of restock predictions
    def predict_restock_needs(days_ahead = 30)
      restock_prediction_service.predict_restock_needs(days_ahead)
    end

    # Revenue prediction - delegates to RevenueForecastService
    # @param days_ahead [Integer] Number of days to forecast (default: 30)
    # @return [Hash] Revenue forecast data
    def predict_revenue(days_ahead = 30)
      revenue_forecast_service.predict_revenue(days_ahead)
    end

    private

    # Lazy-load specialized services to avoid unnecessary instantiation
    def demand_forecast_service
      @demand_forecast_service ||= Analytics::Forecasting::DemandForecastService.new(business)
    end

    def pricing_optimization_service
      @pricing_optimization_service ||= Analytics::Pricing::OptimizationService.new(business)
    end

    def anomaly_detection_service
      @anomaly_detection_service ||= Analytics::Detection::AnomalyDetectionService.new(business)
    end

    def customer_behavior_service
      @customer_behavior_service ||= Analytics::Prediction::CustomerBehaviorService.new(business)
    end

    def staff_scheduling_service
      @staff_scheduling_service ||= Analytics::Optimization::StaffSchedulingService.new(business)
    end

    def restock_prediction_service
      @restock_prediction_service ||= Analytics::Inventory::RestockPredictionService.new(business)
    end

    def revenue_forecast_service
      @revenue_forecast_service ||= Analytics::Revenue::ForecastService.new(business)
    end
  end
end
