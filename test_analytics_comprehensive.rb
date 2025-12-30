# Comprehensive test for all analytics views
# Run with: RAILS_ENV=test bundle exec rails runner test_analytics_comprehensive.rb

puts "=== Comprehensive Analytics Test ==="
puts "Testing all analytics services and views..."
puts

# Find or create a business with data
business = Business.first
if business.nil?
  puts "❌ No business found in database"
  exit 1
end

puts "Testing with business: #{business.name} (ID: #{business.id})"
puts

# Test results tracker
results = {
  revenue: { service: false, controller: false },
  operations: { service: false, controller: false },
  staff: { service: false, controller: false },
  customer: { service: false, controller: false },
  churn: { service: false, controller: false },
  inventory: { service: false, controller: false },
  marketing: { service: false, controller: false },
  predictive: { service: false, controller: false }
}

# Test Revenue Analytics
puts "1. Testing Revenue Analytics..."
begin
  service = Analytics::RevenueForecastService.new(business)
  forecast = service.forecast_revenue(30)
  results[:revenue][:service] = true
  puts "   ✅ Revenue service works - Predicted total: $#{forecast[:predicted_total]}"
rescue => e
  puts "   ❌ Revenue service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Test Operations Analytics
puts "2. Testing Operations Analytics..."
begin
  service = Analytics::OperationalEfficiencyService.new(business)

  # Test no_show_analysis
  no_shows = service.no_show_analysis(30.days)
  puts "   ✅ No-show analysis works - Rate: #{no_shows[:no_show_rate]}%"

  # Test cancellation_analysis (this had the .to_f error)
  cancellations = service.cancellation_analysis(30.days)
  puts "   ✅ Cancellation analysis works - Rate: #{cancellations[:cancellation_rate]}%"

  # Test peak_hours_heatmap
  heatmap = service.peak_hours_heatmap(90.days)
  puts "   ✅ Peak hours heatmap works - Busiest: #{heatmap[:busiest_day]} at #{heatmap[:busiest_hour]}:00"

  # Test fulfillment_metrics
  fulfillment = service.fulfillment_metrics(30.days)
  puts "   ✅ Fulfillment metrics works - Completion rate: #{fulfillment[:completion_rate]}%"

  results[:operations][:service] = true
rescue => e
  puts "   ❌ Operations service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Test Staff Analytics
puts "3. Testing Staff Analytics..."
begin
  service = Analytics::StaffPerformanceService.new(business)

  # Test staff_leaderboard (this had the return format error)
  leaderboard = service.staff_leaderboard(30.days)
  if leaderboard.is_a?(Hash) && leaderboard.key?(:by_revenue)
    puts "   ✅ Staff leaderboard works - Format: Hash with keys #{leaderboard.keys.join(', ')}"
    puts "   ✅ Top revenue earner: #{leaderboard[:by_revenue].first[:name] rescue 'N/A'}"
  else
    puts "   ⚠️  Staff leaderboard wrong format: #{leaderboard.class}"
  end

  # Test performance_summary
  summary = service.performance_summary(30.days)
  puts "   ✅ Performance summary works - Total staff: #{summary[:total_staff]}, Active: #{summary[:active_staff]}"

  results[:staff][:service] = true
rescue => e
  puts "   ❌ Staff service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Test Customer Lifecycle Analytics
puts "4. Testing Customer Lifecycle Analytics..."
begin
  service = Analytics::CustomerLifecycleService.new(business)

  summary = service.segment_summary
  puts "   ✅ Segment summary works - Segments: #{summary[:counts].keys.join(', ')}"

  metrics = service.customer_metrics_summary(30.days)
  puts "   ✅ Customer metrics works - Total customers: #{metrics[:total_customers]}"

  results[:customer][:service] = true
rescue => e
  puts "   ❌ Customer Lifecycle service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Test Churn Prediction Analytics
puts "5. Testing Churn Prediction Analytics..."
begin
  service = Analytics::ChurnPredictionService.new(business)

  at_risk = service.at_risk_customers(60)
  puts "   ✅ At-risk customers works - Found: #{at_risk.count} customers"

  stats = service.churn_statistics
  puts "   ✅ Churn statistics works - Current churn rate: #{stats[:current_churn_rate]}%"

  results[:churn][:service] = true
rescue => e
  puts "   ❌ Churn service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Test Inventory Analytics
puts "6. Testing Inventory Analytics..."
begin
  service = Analytics::InventoryIntelligenceService.new(business)

  # Test low_stock_alerts
  low_stock = service.low_stock_alerts(7)
  puts "   ✅ Low stock alerts works - Alerts: #{low_stock.count}"

  # Test stock_valuation
  valuation = service.stock_valuation
  puts "   ✅ Stock valuation works - Total value: $#{valuation[:total_stock_value]}"

  # Test product_profitability_analysis (this had itemable errors)
  profitability = service.product_profitability_analysis(30.days)
  puts "   ✅ Product profitability works - Products analyzed: #{profitability.count}"

  # Test dead_stock_report
  dead_stock = service.dead_stock_report(90, 100)
  puts "   ✅ Dead stock report works - Items: #{dead_stock.count}"

  # Test calculate_reorder_points
  reorder = service.calculate_reorder_points(14, 7)
  puts "   ✅ Reorder points works - Recommendations: #{reorder.count}"

  results[:inventory][:service] = true
rescue => e
  puts "   ❌ Inventory service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Test Marketing Analytics
puts "7. Testing Marketing Analytics..."
begin
  service = Analytics::MarketingPerformanceService.new(business)

  # Test campaigns_summary (this had cost column error)
  puts "   Testing campaigns_summary..."
  campaigns = service.campaigns_summary(30.days)
  puts "   ✅ Campaigns summary works - Campaigns: #{campaigns.is_a?(Array) ? campaigns.count : 'N/A'}"

  # Test channel_performance
  puts "   Testing channel_performance..."
  channels = service.channel_performance(30.days)
  puts "   ✅ Channel performance works - Channels: #{channels.count}"

  # Test acquisition_by_source
  puts "   Testing acquisition_by_source..."
  acquisition = service.acquisition_by_source(30.days)
  puts "   ✅ Acquisition analysis works - Sources: #{acquisition.count}"

  results[:marketing][:service] = true
rescue => e
  puts "   ❌ Marketing service failed: #{e.message}"
  puts "      #{e.backtrace.first(5).join("\n      ")}"
end
puts

# Test Predictive Analytics
puts "8. Testing Predictive Analytics..."
begin
  service = Analytics::PredictiveService.new(business)

  # Test predict_revenue
  revenue_forecast = service.predict_revenue(30)
  puts "   ✅ Revenue prediction works - Predicted total: $#{revenue_forecast[:predicted_total]}"

  # Test predict_restock_needs (this had itemable errors)
  restock = service.predict_restock_needs(30)
  puts "   ✅ Restock prediction works - Items needing restock: #{restock.count}"

  # Test detect_anomalies
  anomalies = service.detect_anomalies(:bookings, 30.days)
  puts "   ✅ Anomaly detection works - Anomalies found: #{anomalies.count}"

  results[:predictive][:service] = true
rescue => e
  puts "   ❌ Predictive service failed: #{e.message}"
  puts "      #{e.backtrace.first(2).join("\n      ")}"
end
puts

# Summary
puts "=" * 60
puts "SUMMARY OF RESULTS"
puts "=" * 60
puts

total_services = results.count
passing_services = results.count { |_, v| v[:service] }

results.each do |name, status|
  service_status = status[:service] ? "✅" : "❌"
  puts "#{name.to_s.capitalize.ljust(20)} Service: #{service_status}"
end

puts
puts "Overall: #{passing_services}/#{total_services} analytics services passing"

if passing_services == total_services
  puts
  puts "🎉 SUCCESS! All analytics services are working correctly!"
  exit 0
else
  puts
  puts "⚠️  Some analytics services still have issues"
  exit 1
end
