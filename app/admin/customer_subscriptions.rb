# frozen_string_literal: true

ActiveAdmin.register CustomerSubscription do
  menu parent: 'Subscriptions', priority: 1

  # Scopes for filtering
  scope :all, default: true
  scope :active
  scope :cancelled
  scope :paused
  scope :expired
  scope :failed

  # Filters
  filter :business, as: :select, collection: -> { Business.order(:name) }
  filter :tenant_customer, as: :select, collection: -> { TenantCustomer.order(:email) }
  filter :subscription_type, as: :select, collection: CustomerSubscription.subscription_types
  filter :status, as: :select, collection: CustomerSubscription.statuses
  filter :frequency, as: :select, collection: CustomerSubscription.billing_cycles
  filter :subscription_price
  filter :created_at
  filter :next_billing_date
  filter :cancelled_at
  filter :stripe_subscription_id

  # Index page
  index do
    selectable_column
    id_column
    
    column :business do |subscription|
      link_to subscription.business.name, admin_business_path(subscription.business)
    end
    
    column :customer do |subscription|
      link_to subscription.tenant_customer.email, admin_user_path(subscription.tenant_customer.user) if subscription.tenant_customer.user
    end
    
    column :item do |subscription|
      if subscription.product
        link_to subscription.product.name, admin_product_path(subscription.product)
      elsif subscription.service
        link_to subscription.service.name, admin_service_path(subscription.service)
      end
    end
    
    column :type do |subscription|
      subscription.subscription_type.humanize
    end
    
    column :status do |subscription|
      status_tag subscription.status, class: subscription_status_class(subscription.status)
    end
    
    column :frequency do |subscription|
      subscription.frequency.humanize
    end
    
    column :price do |subscription|
      number_to_currency(subscription.subscription_price)
    end
    
    column :quantity
    
    column :next_billing do |subscription|
      subscription.next_billing_date&.strftime('%m/%d/%Y')
    end
    
    column :stripe_status do |subscription|
      if subscription.stripe_subscription_id.present?
        status_tag 'Connected', class: 'ok'
      else
        status_tag 'Not Connected', class: 'error'
      end
    end
    
    column :created_at do |subscription|
      subscription.created_at.strftime('%m/%d/%Y')
    end
    
    actions
  end

  # Show page
  show do
    attributes_table do
      row :id
      row :business do |subscription|
        link_to subscription.business.name, admin_business_path(subscription.business)
      end
      row :customer do |subscription|
        div do
          strong subscription.tenant_customer.full_name
        end
        div do
          mail_to subscription.tenant_customer.email
        end
        div do
          link_to "View User", admin_user_path(subscription.tenant_customer.user) if subscription.tenant_customer.user
        end
      end
      row :subscription_type
      row :item do |subscription|
        if subscription.product
          div do
            strong "Product: "
            link_to subscription.product.name, admin_product_path(subscription.product)
          end
        elsif subscription.service
          div do
            strong "Service: "
            link_to subscription.service.name, admin_service_path(subscription.service)
          end
        end
      end
      row :status do |subscription|
        status_tag subscription.status, class: subscription_status_class(subscription.status)
      end
      row :frequency
      row :quantity
      row :subscription_price do |subscription|
        number_to_currency(subscription.subscription_price)
      end
      row :start_date
      row :next_billing_date
      row :last_billing_date
      row :cancelled_at
      row :cancellation_reason
      row :stripe_subscription_id do |subscription|
        if subscription.stripe_subscription_id.present?
          div do
            code subscription.stripe_subscription_id
          end
          div do
            link_to "View in Stripe", "https://dashboard.stripe.com/subscriptions/#{subscription.stripe_subscription_id}", 
                    target: '_blank', class: 'button'
          end
        else
          span "Not connected to Stripe", class: 'empty'
        end
      end
      row :customer_preferences do |subscription|
        if subscription.customer_preferences.present?
          ul do
            subscription.customer_preferences.each do |key, value|
              li "#{key.humanize}: #{value}"
            end
          end
        else
          span "No preferences set", class: 'empty'
        end
      end
      row :created_at
      row :updated_at
    end

    # Subscription Transactions
    panel "Subscription Transactions" do
      table_for subscription.subscription_transactions.order(created_at: :desc) do
        column :id
        column :transaction_type do |transaction|
          status_tag transaction.transaction_type, class: transaction_type_class(transaction.transaction_type)
        end
        column :status do |transaction|
          status_tag transaction.status, class: transaction_status_class(transaction.status)
        end
        column :amount do |transaction|
          number_to_currency(transaction.amount)
        end
        column :processed_date
        column :stripe_invoice_id do |transaction|
          if transaction.stripe_invoice_id.present?
            link_to "View Invoice", "https://dashboard.stripe.com/invoices/#{transaction.stripe_invoice_id}", 
                    target: '_blank', class: 'button small'
          end
        end
        column :failure_reason
        column :created_at
      end
    end

    # Related Orders (for product subscriptions)
    if subscription.product_subscription?
      panel "Subscription Orders" do
        orders = Order.where(subscription_id: subscription.id).order(created_at: :desc).limit(10)
        if orders.any?
          table_for orders do
            column :id do |order|
              link_to order.id, admin_order_path(order)
            end
            column :status do |order|
              status_tag order.status
            end
            column :total_amount do |order|
              number_to_currency(order.total_amount)
            end
            column :created_at
          end
        else
          div "No orders created yet", class: 'empty'
        end
      end
    end

    # Related Bookings (for service subscriptions)
    if subscription.service_subscription?
      panel "Subscription Bookings" do
        bookings = Booking.where(subscription_id: subscription.id).order(start_time: :desc).limit(10)
        if bookings.any?
          table_for bookings do
            column :id do |booking|
              link_to booking.id, admin_booking_path(booking)
            end
            column :status do |booking|
              status_tag booking.status
            end
            column :start_time
            column :staff_member do |booking|
              booking.staff_member&.name
            end
            column :created_at
          end
        else
          div "No bookings created yet", class: 'empty'
        end
      end
    end

    active_admin_comments
  end

  # Form for editing
  form do |f|
    f.inputs "Subscription Details" do
      f.input :business, as: :select, collection: Business.order(:name), include_blank: false
      f.input :tenant_customer, as: :select, 
              collection: TenantCustomer.joins(:user).order('users.email').map { |tc| [tc.email, tc.id] },
              include_blank: false
      f.input :subscription_type, as: :select, collection: CustomerSubscription.subscription_types, include_blank: false
      f.input :quantity
      f.input :frequency, as: :select, collection: CustomerSubscription.frequencies, include_blank: false
      f.input :subscription_price
      f.input :status, as: :select, collection: CustomerSubscription.statuses, include_blank: false
    end

    f.inputs "Billing Information" do
      f.input :start_date, as: :date_picker
      f.input :next_billing_date, as: :date_picker
      f.input :last_billing_date, as: :date_picker
    end

    f.inputs "Stripe Integration" do
      f.input :stripe_subscription_id
    end

    f.inputs "Cancellation" do
      f.input :cancelled_at, as: :date_time_picker
      f.input :cancellation_reason
    end

    f.actions
  end

  # Batch actions
  batch_action :cancel_subscriptions do |ids|
    batch_action_collection.find(ids).each do |subscription|
      if subscription.active?
        subscription.update!(status: :cancelled, cancelled_at: Time.current, cancellation_reason: 'Admin cancellation')
        # Cancel in Stripe if connected
        if subscription.stripe_subscription_id.present?
          SubscriptionStripeService.new(subscription).cancel_stripe_subscription!
        end
      end
    end
    redirect_to collection_path, notice: "#{ids.count} subscriptions cancelled."
  end

  batch_action :pause_subscriptions do |ids|
    batch_action_collection.find(ids).each do |subscription|
      if subscription.active?
        subscription.update!(status: :paused)
        # Pause in Stripe if connected
        if subscription.stripe_subscription_id.present?
          SubscriptionStripeService.new(subscription).pause_stripe_subscription!
        end
      end
    end
    redirect_to collection_path, notice: "#{ids.count} subscriptions paused."
  end

  # Member actions
  member_action :cancel_subscription, method: :post do
    if resource.active?
      resource.update!(status: :cancelled, cancelled_at: Time.current, cancellation_reason: 'Admin cancellation')
      # Cancel in Stripe if connected
      if resource.stripe_subscription_id.present?
        SubscriptionStripeService.new(resource).cancel_stripe_subscription!
      end
      redirect_to resource_path, notice: 'Subscription cancelled successfully.'
    else
      redirect_to resource_path, alert: 'Subscription cannot be cancelled.'
    end
  end

  member_action :pause_subscription, method: :post do
    if resource.active?
      resource.update!(status: :paused)
      # Pause in Stripe if connected
      if resource.stripe_subscription_id.present?
        SubscriptionStripeService.new(resource).pause_stripe_subscription!
      end
      redirect_to resource_path, notice: 'Subscription paused successfully.'
    else
      redirect_to resource_path, alert: 'Subscription cannot be paused.'
    end
  end

  member_action :resume_subscription, method: :post do
    if resource.paused?
      resource.update!(status: :active)
      # Resume in Stripe if connected
      if resource.stripe_subscription_id.present?
        SubscriptionStripeService.new(resource).resume_stripe_subscription!
      end
      redirect_to resource_path, notice: 'Subscription resumed successfully.'
    else
      redirect_to resource_path, alert: 'Subscription cannot be resumed.'
    end
  end

  # Action items (buttons on show page)
  action_item :cancel, only: :show, if: proc { resource.active? } do
    link_to 'Cancel Subscription', cancel_subscription_admin_customer_subscription_path(resource), 
            method: :post, class: 'button', 
            confirm: 'Are you sure you want to cancel this subscription?'
  end

  action_item :pause, only: :show, if: proc { resource.active? } do
    link_to 'Pause Subscription', pause_subscription_admin_customer_subscription_path(resource), 
            method: :post, class: 'button'
  end

  action_item :resume, only: :show, if: proc { resource.paused? } do
    link_to 'Resume Subscription', resume_subscription_admin_customer_subscription_path(resource), 
            method: :post, class: 'button'
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

    def transaction_type_class(type)
      case type.to_s
      when 'billing', 'signup' then 'ok'
      when 'failed_payment' then 'error'
      when 'refund' then 'warning'
      else 'default'
      end
    end

    def transaction_status_class(status)
      case status.to_s
      when 'completed' then 'ok'
      when 'failed' then 'error'
      when 'pending' then 'warning'
      else 'default'
      end
    end
  end
end 
 
 
 
 