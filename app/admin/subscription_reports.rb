# frozen_string_literal: true

ActiveAdmin.register_page "Subscription Reports" do
  menu parent: 'Subscriptions', priority: 4, label: 'Reports'

  content title: 'Subscription Reports' do
    # Report Generation Form
    div class: 'report_form' do
      form action: admin_subscription_reports_path, method: :get do |f|
        div class: 'form_row' do
          div class: 'form_field' do
            label 'Report Type:'
            select name: 'report_type' do
              option value: 'revenue', selected: params[:report_type] == 'revenue' do
                'Revenue Report'
              end
              option value: 'churn', selected: params[:report_type] == 'churn' do
                'Churn Analysis'
              end
              option value: 'business_performance', selected: params[:report_type] == 'business_performance' do
                'Business Performance'
              end
              option value: 'customer_lifetime', selected: params[:report_type] == 'customer_lifetime' do
                'Customer Lifetime Value'
              end
              option value: 'failed_payments', selected: params[:report_type] == 'failed_payments' do
                'Failed Payments Report'
              end
            end
          end

          div class: 'form_field' do
            label 'Date Range:'
            input name: 'start_date', type: 'date', value: params[:start_date] || 30.days.ago.to_date
            span ' to '
            input name: 'end_date', type: 'date', value: params[:end_date] || Date.current
          end

          div class: 'form_field' do
            label 'Business Tier:'
            select name: 'business_tier' do
              option value: '', selected: params[:business_tier].blank? do
                'All Tiers'
              end
              option value: 'free', selected: params[:business_tier] == 'free' do
                'Free'
              end
              option value: 'standard', selected: params[:business_tier] == 'standard' do
                'Standard'
              end
              option value: 'premium', selected: params[:business_tier] == 'premium' do
                'Premium'
              end
            end
          end

          div class: 'form_field' do
            input type: 'submit', value: 'Generate Report', class: 'button primary'
            link_to 'Export CSV', admin_subscription_reports_path(params.merge(format: 'csv')), class: 'button'
          end
        end
      end
    end

    # Report Content
    if params[:report_type].present?
      start_date = params[:start_date]&.to_date || 30.days.ago.to_date
      end_date = params[:end_date]&.to_date || Date.current
      business_tier = params[:business_tier].presence

      case params[:report_type]
      when 'revenue'
        # Revenue Report
        panel "Revenue Report (#{start_date.strftime('%m/%d/%Y')} - #{end_date.strftime('%m/%d/%Y')})" do
          # Base query
          subscriptions = CustomerSubscription.joins(:business)
          subscriptions = subscriptions.where(businesses: { tier: business_tier }) if business_tier.present?

          # Revenue by month
          monthly_revenue = subscriptions.active
                                       .where(created_at: start_date..end_date)
                                       .group_by_month(:created_at)
                                       .sum(:subscription_price)

          table do
            tr do
              th 'Month'
              th 'New Subscriptions'
              th 'New MRR'
              th 'Total Active'
              th 'Total MRR'
            end
            monthly_revenue.each do |month, new_mrr|
              month_start = month.beginning_of_month
              month_end = month.end_of_month
              new_subs = subscriptions.where(created_at: month_start..month_end).count
              total_active = subscriptions.active.where(created_at: ..month_end).count
              total_mrr = subscriptions.active.where(created_at: ..month_end).sum(:subscription_price)
              
              tr do
                td month.strftime('%B %Y')
                td new_subs
                td number_to_currency(new_mrr)
                td total_active
                td number_to_currency(total_mrr)
              end
            end
          end

          # Revenue by subscription type
          h3 'Revenue by Subscription Type'
          type_revenue = subscriptions.active
                                    .where(created_at: start_date..end_date)
                                    .group(:subscription_type)
                                    .sum(:subscription_price)

          table do
            tr do
              th 'Subscription Type'
              th 'Count'
              th 'Revenue'
              th 'Average Price'
            end
            type_revenue.each do |type, revenue|
              count = subscriptions.active.where(subscription_type: type, created_at: start_date..end_date).count
              avg_price = count > 0 ? revenue / count : 0
              tr do
                td type.humanize
                td count
                td number_to_currency(revenue)
                td number_to_currency(avg_price)
              end
            end
          end
        end

      when 'churn'
        # Churn Analysis Report
        panel "Churn Analysis (#{start_date.strftime('%m/%d/%Y')} - #{end_date.strftime('%m/%d/%Y')})" do
          subscriptions = CustomerSubscription.joins(:business)
          subscriptions = subscriptions.where(businesses: { tier: business_tier }) if business_tier.present?

          # Churn by month
          monthly_churn = subscriptions.cancelled
                                     .where(cancelled_at: start_date..end_date)
                                     .group_by_month(:cancelled_at)
                                     .count

          table do
            tr do
              th 'Month'
              th 'Cancelled Subscriptions'
              th 'Active at Start'
              th 'Churn Rate'
              th 'Lost MRR'
            end
            monthly_churn.each do |month, cancelled_count|
              month_start = month.beginning_of_month
              active_start = subscriptions.where(created_at: ..month_start)
                                        .where('cancelled_at IS NULL OR cancelled_at > ?', month_start).count
              churn_rate = active_start > 0 ? (cancelled_count.to_f / active_start * 100).round(2) : 0
              lost_mrr = subscriptions.cancelled
                                    .where(cancelled_at: month_start..month.end_of_month)
                                    .sum(:subscription_price)
              
              tr do
                td month.strftime('%B %Y')
                td cancelled_count
                td active_start
                td "#{churn_rate}%"
                td number_to_currency(lost_mrr)
              end
            end
          end

          # Churn reasons
          h3 'Cancellation Reasons'
          churn_reasons = subscriptions.cancelled
                                     .where(cancelled_at: start_date..end_date)
                                     .group(:cancellation_reason)
                                     .count

          table do
            tr do
              th 'Reason'
              th 'Count'
              th 'Percentage'
            end
            total_cancelled = churn_reasons.values.sum
            churn_reasons.each do |reason, count|
              percentage = total_cancelled > 0 ? (count.to_f / total_cancelled * 100).round(1) : 0
              tr do
                td reason.presence || 'No reason provided'
                td count
                td "#{percentage}%"
              end
            end
          end
        end

      when 'business_performance'
        # Business Performance Report
        panel "Business Performance (#{start_date.strftime('%m/%d/%Y')} - #{end_date.strftime('%m/%d/%Y')})" do
          businesses_query = Business.joins(:customer_subscriptions)
          businesses_query = businesses_query.where(tier: business_tier) if business_tier.present?

          business_stats = businesses_query
                          .where(customer_subscriptions: { created_at: start_date..end_date })
                          .group('businesses.id', 'businesses.name', 'businesses.tier')
                          .select('businesses.id, businesses.name, businesses.tier,
                                   COUNT(customer_subscriptions.id) as subscription_count,
                                   SUM(customer_subscriptions.subscription_price) as total_revenue,
                                   AVG(customer_subscriptions.subscription_price) as avg_price')

          table do
            tr do
              th 'Business'
              th 'Tier'
              th 'New Subscriptions'
              th 'Total Revenue'
              th 'Average Price'
              th 'Active Subscriptions'
            end
            business_stats.each do |business|
              active_count = CustomerSubscription.active.where(business_id: business.id).count
              tr do
                td link_to(business.name, admin_business_path(business.id))
                td status_tag(business.tier)
                td business.subscription_count
                td number_to_currency(business.total_revenue)
                td number_to_currency(business.avg_price)
                td active_count
              end
            end
          end
        end

      when 'customer_lifetime'
        # Customer Lifetime Value Report
        panel "Customer Lifetime Value Analysis (#{start_date.strftime('%m/%d/%Y')} - #{end_date.strftime('%m/%d/%Y')})" do
          # Calculate CLV metrics
          active_customers = TenantCustomer.joins(:customer_subscriptions)
                                         .where(customer_subscriptions: { status: 'active' })
                                         .distinct

          if business_tier.present?
            active_customers = active_customers.joins(customer_subscriptions: :business)
                                             .where(businesses: { tier: business_tier })
          end

          # Average subscription duration
          completed_subscriptions = CustomerSubscription.cancelled
                                                       .where(cancelled_at: start_date..end_date)
          
          if business_tier.present?
            completed_subscriptions = completed_subscriptions.joins(:business)
                                                           .where(businesses: { tier: business_tier })
          end

          avg_duration_days = completed_subscriptions.average('EXTRACT(EPOCH FROM (cancelled_at - created_at)) / 86400') || 0
          avg_duration_months = (avg_duration_days / 30.0).round(1)

          # CLV calculation
          avg_monthly_revenue = CustomerSubscription.active.average(:subscription_price) || 0
          estimated_clv = avg_monthly_revenue * avg_duration_months

          div class: 'clv-metrics' do
            div class: 'metric' do
              h4 'Average Customer Lifetime'
              p "#{avg_duration_months} months"
            end
            div class: 'metric' do
              h4 'Average Monthly Revenue per Customer'
              p number_to_currency(avg_monthly_revenue)
            end
            div class: 'metric' do
              h4 'Estimated Customer Lifetime Value'
              p number_to_currency(estimated_clv)
            end
          end

          # Top customers by revenue
          h3 'Top Customers by Subscription Revenue'
          top_customers = TenantCustomer.joins(:customer_subscriptions)
                                      .where(customer_subscriptions: { status: 'active' })
                                      .group('tenant_customers.id', 'tenant_customers.name', 'tenant_customers.email')
                                      .sum('customer_subscriptions.subscription_price')
                                      .sort_by { |_, revenue| -revenue }
                                      .first(20)

          table do
            tr do
              th 'Customer'
              th 'Email'
              th 'Active Subscriptions'
              th 'Monthly Revenue'
            end
            top_customers.each do |customer_data, revenue|
              customer = TenantCustomer.find(customer_data[0])
              subscription_count = customer.customer_subscriptions.active.count
              tr do
                td customer.name
                td mail_to(customer.email)
                td subscription_count
                td number_to_currency(revenue)
              end
            end
          end
        end

      when 'failed_payments'
        # Failed Payments Report
        panel "Failed Payments Report (#{start_date.strftime('%m/%d/%Y')} - #{end_date.strftime('%m/%d/%Y')})" do
          failed_transactions = SubscriptionTransaction.failed
                                                      .includes(:customer_subscription, :business, :tenant_customer)
                                                      .where(created_at: start_date..end_date)

          if business_tier.present?
            failed_transactions = failed_transactions.joins(:business)
                                                   .where(businesses: { tier: business_tier })
          end

          # Summary stats
          total_failed = failed_transactions.count
          total_failed_amount = failed_transactions.sum(:amount)
          unique_customers = failed_transactions.joins(:tenant_customer).distinct.count('tenant_customers.id')

          div class: 'failed-payments-summary' do
            div class: 'metric' do
              h4 'Total Failed Transactions'
              p total_failed
            end
            div class: 'metric' do
              h4 'Total Failed Amount'
              p number_to_currency(total_failed_amount)
            end
            div class: 'metric' do
              h4 'Affected Customers'
              p unique_customers
            end
          end

          # Failed transactions table
          table_for failed_transactions.order(created_at: :desc) do
            column :id do |transaction|
              link_to transaction.id, admin_subscription_transaction_path(transaction)
            end
            column :business do |transaction|
              link_to transaction.business.name, admin_business_path(transaction.business)
            end
            column :customer do |transaction|
              transaction.tenant_customer.email
            end
            column :amount do |transaction|
              number_to_currency(transaction.amount)
            end
            column :failure_reason
            column :created_at do |transaction|
              transaction.created_at.strftime('%m/%d/%Y %H:%M')
            end
          end
        end
      end
    else
      # Default message
      div class: 'empty-state' do
        h3 'Select a report type to generate subscription insights'
        p 'Choose from revenue analysis, churn reports, business performance, customer lifetime value, or failed payments analysis.'
      end
    end
  end

  # CSV export functionality
  controller do
    def index
      respond_to do |format|
        format.html { super }
        format.csv { send_csv_report }
      end
    end

    private

    def send_csv_report
      case params[:report_type]
      when 'revenue'
        send_data generate_revenue_csv, filename: "subscription_revenue_report_#{Date.current}.csv"
      when 'churn'
        send_data generate_churn_csv, filename: "subscription_churn_report_#{Date.current}.csv"
      when 'business_performance'
        send_data generate_business_performance_csv, filename: "business_performance_report_#{Date.current}.csv"
      when 'failed_payments'
        send_data generate_failed_payments_csv, filename: "failed_payments_report_#{Date.current}.csv"
      else
        redirect_to admin_subscription_reports_path, alert: 'Please select a report type for CSV export.'
      end
    end

    def generate_revenue_csv
      CSV.generate(headers: true) do |csv|
        csv << ['Date', 'New Subscriptions', 'New MRR', 'Total Active', 'Total MRR']
        # Add revenue data rows here
      end
    end

    def generate_churn_csv
      CSV.generate(headers: true) do |csv|
        csv << ['Date', 'Cancelled Subscriptions', 'Churn Rate', 'Lost MRR', 'Reason']
        # Add churn data rows here
      end
    end

    def generate_business_performance_csv
      CSV.generate(headers: true) do |csv|
        csv << ['Business', 'Tier', 'New Subscriptions', 'Total Revenue', 'Average Price', 'Active Subscriptions']
        # Add business performance data rows here
      end
    end

    def generate_failed_payments_csv
      CSV.generate(headers: true) do |csv|
        csv << ['Date', 'Business', 'Customer', 'Amount', 'Failure Reason']
        # Add failed payments data rows here
      end
    end
  end

  # Custom CSS for reports
  content do
    style do
      raw <<~CSS
        .report_form {
          background: #f8f9fa;
          padding: 20px;
          border-radius: 8px;
          margin-bottom: 30px;
        }
        
        .form_row {
          display: flex;
          gap: 20px;
          align-items: end;
          flex-wrap: wrap;
        }
        
        .form_field {
          display: flex;
          flex-direction: column;
          gap: 5px;
        }
        
        .form_field label {
          font-weight: bold;
          font-size: 14px;
        }
        
        .form_field select,
        .form_field input[type="date"] {
          padding: 8px;
          border: 1px solid #ddd;
          border-radius: 4px;
          font-size: 14px;
        }
        
        .button {
          padding: 10px 20px;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          text-decoration: none;
          display: inline-block;
          font-size: 14px;
        }
        
        .button.primary {
          background: #5b9bd5;
          color: white;
        }
        
        .button:not(.primary) {
          background: #6c757d;
          color: white;
        }
        
        .clv-metrics,
        .failed-payments-summary {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 20px;
          margin: 20px 0;
        }
        
        .metric {
          background: white;
          border: 1px solid #ddd;
          border-radius: 8px;
          padding: 20px;
          text-align: center;
        }
        
        .metric h4 {
          margin: 0 0 10px 0;
          color: #666;
          font-size: 14px;
        }
        
        .metric p {
          margin: 0;
          font-size: 24px;
          font-weight: bold;
          color: #333;
        }
        
        .empty-state {
          text-align: center;
          padding: 60px 20px;
          color: #666;
        }
        
        .empty-state h3 {
          margin-bottom: 10px;
        }
      CSS
    end
  end
end 
 
 
 
 