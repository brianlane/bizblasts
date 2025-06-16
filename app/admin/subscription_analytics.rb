# frozen_string_literal: true

ActiveAdmin.register_page "Subscription Analytics" do
  menu parent: 'Subscriptions', priority: 3, label: 'Analytics'

  content title: 'Subscription Analytics Dashboard' do
    # Date range filter
    div class: 'filter_form' do
      form action: admin_subscription_analytics_path, method: :get do |f|
        div class: 'filter_form_field' do
          label 'Date Range:'
          input name: 'start_date', type: 'date', value: params[:start_date] || 30.days.ago.to_date
          span ' to '
          input name: 'end_date', type: 'date', value: params[:end_date] || Date.current
          input type: 'submit', value: 'Filter', class: 'button'
        end
      end
    end

    # Date range setup
    start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    end_date = params[:end_date]&.to_date || Date.current

    # Key Metrics Cards
    div class: 'dashboard-stats' do
      # Total Active Subscriptions
      div class: 'stat-card' do
        h3 'Active Subscriptions'
        div class: 'stat-number' do
          CustomerSubscription.active.count
        end
        div class: 'stat-change' do
          change = CustomerSubscription.active.where(created_at: start_date..end_date).count
          "+#{change} this period"
        end
      end

      # Monthly Recurring Revenue
      div class: 'stat-card' do
        h3 'Monthly Recurring Revenue'
        div class: 'stat-number' do
          number_to_currency(CustomerSubscription.active.sum(:subscription_price))
        end
        div class: 'stat-change' do
          new_mrr = CustomerSubscription.active.where(created_at: start_date..end_date).sum(:subscription_price)
          "+#{number_to_currency(new_mrr)} this period"
        end
      end

      # Churn Rate
      div class: 'stat-card' do
        h3 'Churn Rate'
        div class: 'stat-number' do
          total_active = CustomerSubscription.active.count
          cancelled_this_period = CustomerSubscription.cancelled.where(cancelled_at: start_date..end_date).count
          churn_rate = total_active > 0 ? (cancelled_this_period.to_f / total_active * 100).round(2) : 0
          "#{churn_rate}%"
        end
        div class: 'stat-change' do
          "#{cancelled_this_period} cancelled this period"
        end
      end

      # Average Revenue Per User
      div class: 'stat-card' do
        h3 'Average Revenue Per User'
        div class: 'stat-number' do
          active_subs = CustomerSubscription.active
          arpu = active_subs.count > 0 ? active_subs.average(:subscription_price) : 0
          number_to_currency(arpu)
        end
      end
    end

    # Subscription Status Breakdown
    panel "Subscription Status Breakdown" do
      table_for CustomerSubscription.group(:status).count.map { |status, count| 
        OpenStruct.new(status: status, count: count, percentage: (count.to_f / CustomerSubscription.count * 100).round(1))
      } do
        column :status do |row|
          status_tag row.status, class: subscription_status_class(row.status)
        end
        column :count
        column :percentage do |row|
          "#{row.percentage}%"
        end
      end
    end

    # Revenue by Business Type
    panel "Revenue by Subscription Type" do
      product_revenue = CustomerSubscription.active.where(subscription_type: 'product').sum(:subscription_price)
      service_revenue = CustomerSubscription.active.where(subscription_type: 'service').sum(:subscription_price)
      
      table do
        tr do
          th 'Subscription Type'
          th 'Active Subscriptions'
          th 'Monthly Revenue'
          th 'Average Price'
        end
        tr do
          td 'Product Subscriptions'
          td CustomerSubscription.active.where(subscription_type: 'product').count
          td number_to_currency(product_revenue)
          td number_to_currency(CustomerSubscription.active.where(subscription_type: 'product').average(:subscription_price) || 0)
        end
        tr do
          td 'Service Subscriptions'
          td CustomerSubscription.active.where(subscription_type: 'service').count
          td number_to_currency(service_revenue)
          td number_to_currency(CustomerSubscription.active.where(subscription_type: 'service').average(:subscription_price) || 0)
        end
      end
    end

    # Top Businesses by Subscription Revenue
    panel "Top Businesses by Subscription Revenue" do
      top_businesses = Business.joins(:customer_subscriptions)
                              .where(customer_subscriptions: { status: 'active' })
                              .group('businesses.id', 'businesses.name')
                              .sum('customer_subscriptions.subscription_price')
                              .sort_by { |_, revenue| -revenue }
                              .first(10)

      table do
        tr do
          th 'Business'
          th 'Active Subscriptions'
          th 'Monthly Revenue'
          th 'Tier'
        end
        top_businesses.each do |business_data, revenue|
          business = Business.find(business_data[0])
          tr do
            td link_to(business.name, admin_business_path(business))
            td business.customer_subscriptions.active.count
            td number_to_currency(revenue)
            td status_tag(business.tier)
          end
        end
      end
    end

    # Recent Subscription Activity
    panel "Recent Subscription Activity" do
      recent_subscriptions = CustomerSubscription.includes(:business, :tenant_customer)
                                                .order(created_at: :desc)
                                                .limit(20)

      table_for recent_subscriptions do
        column :id do |subscription|
          link_to subscription.id, admin_customer_subscription_path(subscription)
        end
        column :business do |subscription|
          link_to subscription.business.name, admin_business_path(subscription.business)
        end
        column :customer do |subscription|
          subscription.tenant_customer.email
        end
        column :type do |subscription|
          subscription.subscription_type.humanize
        end
        column :status do |subscription|
          status_tag subscription.status, class: subscription_status_class(subscription.status)
        end
        column :price do |subscription|
          number_to_currency(subscription.subscription_price)
        end
        column :created_at do |subscription|
          subscription.created_at.strftime('%m/%d/%Y %H:%M')
        end
      end
    end

    # Failed Transactions
    panel "Recent Failed Transactions" do
      failed_transactions = SubscriptionTransaction.failed
                                                  .includes(:customer_subscription, :business, :tenant_customer)
                                                  .order(created_at: :desc)
                                                  .limit(10)

      if failed_transactions.any?
        table_for failed_transactions do
          column :id do |transaction|
            link_to transaction.id, admin_subscription_transaction_path(transaction)
          end
          column :subscription do |transaction|
            link_to "Subscription ##{transaction.customer_subscription.id}", 
                    admin_customer_subscription_path(transaction.customer_subscription)
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
      else
        div "No failed transactions in the recent period", class: 'empty'
      end
    end

    # Subscription Growth Chart Data (for future JavaScript implementation)
    panel "Subscription Growth Trends" do
      growth_data = (start_date..end_date).map do |date|
        {
          date: date,
          new_subscriptions: CustomerSubscription.where(created_at: date.beginning_of_day..date.end_of_day).count,
          cancelled_subscriptions: CustomerSubscription.where(cancelled_at: date.beginning_of_day..date.end_of_day).count,
          total_active: CustomerSubscription.where(created_at: ..date.end_of_day)
                                          .where('cancelled_at IS NULL OR cancelled_at > ?', date.end_of_day).count
        }
      end

      table do
        tr do
          th 'Date'
          th 'New Subscriptions'
          th 'Cancelled'
          th 'Net Growth'
          th 'Total Active'
        end
        growth_data.last(7).each do |data|
          tr do
            td data[:date].strftime('%m/%d/%Y')
            td data[:new_subscriptions]
            td data[:cancelled_subscriptions]
            td data[:new_subscriptions] - data[:cancelled_subscriptions]
            td data[:total_active]
          end
        end
      end
    end
  end

  # Helper methods
  controller do
    private

    def subscription_status_class(status)
      case status.to_s
      when 'active' then 'ok'
      when 'cancelled' then 'error'
      when 'paused' then 'warning'
      when 'payment_failed', 'past_due' then 'error'
      else 'default'
      end
    end
  end

  # Add custom CSS for dashboard
  content do
    style do
      raw <<~CSS
        .dashboard-stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
          gap: 20px;
          margin-bottom: 30px;
        }
        
        .stat-card {
          background: white;
          border: 1px solid #ddd;
          border-radius: 8px;
          padding: 20px;
          text-align: center;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .stat-card h3 {
          margin: 0 0 10px 0;
          color: #666;
          font-size: 14px;
          text-transform: uppercase;
          letter-spacing: 1px;
        }
        
        .stat-number {
          font-size: 32px;
          font-weight: bold;
          color: #333;
          margin-bottom: 5px;
        }
        
        .stat-change {
          font-size: 12px;
          color: #666;
        }
        
        .filter_form {
          background: #f8f9fa;
          padding: 15px;
          border-radius: 5px;
          margin-bottom: 20px;
        }
        
        .filter_form_field {
          display: flex;
          align-items: center;
          gap: 10px;
        }
        
        .filter_form_field label {
          font-weight: bold;
        }
        
        .filter_form_field input[type="date"] {
          padding: 5px;
          border: 1px solid #ddd;
          border-radius: 3px;
        }
        
        .filter_form_field .button {
          background: #5b9bd5;
          color: white;
          border: none;
          padding: 8px 16px;
          border-radius: 3px;
          cursor: pointer;
        }
      CSS
    end
  end
end 
 
 
 
 