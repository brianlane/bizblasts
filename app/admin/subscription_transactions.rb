# frozen_string_literal: true

ActiveAdmin.register SubscriptionTransaction do
  menu parent: 'Subscriptions', priority: 2

  # Scopes for filtering
  scope :all, default: true
  scope :completed
  scope :failed
  scope :pending
  scope :cancelled
  scope :retrying

  # Filters
  filter :customer_subscription, as: :select, collection: -> { CustomerSubscription.joins(:business).order('businesses.name') }
  filter :business, as: :select, collection: -> { Business.order(:name) }
  filter :transaction_type, as: :select, collection: SubscriptionTransaction.transaction_types
  filter :status, as: :select, collection: SubscriptionTransaction.statuses
  filter :amount
  filter :processed_date
  filter :created_at
  filter :stripe_invoice_id
  filter :stripe_payment_intent_id

  # Index page
  index do
    selectable_column
    id_column
    
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
    
    column :type do |transaction|
      status_tag transaction.transaction_type, class: transaction_type_class(transaction.transaction_type)
    end
    
    column :status do |transaction|
      status_tag transaction.status, class: transaction_status_class(transaction.status)
    end
    
    column :amount do |transaction|
      number_to_currency(transaction.amount)
    end
    
    column :processed_date do |transaction|
      transaction.processed_date&.strftime('%m/%d/%Y')
    end
    
    column :stripe_status do |transaction|
      if transaction.stripe_invoice_id.present?
        status_tag 'Stripe Invoice', class: 'ok'
      elsif transaction.stripe_payment_intent_id.present?
        status_tag 'Stripe Payment', class: 'ok'
      else
        status_tag 'No Stripe Data', class: 'warning'
      end
    end
    
    column :created_at do |transaction|
      transaction.created_at.strftime('%m/%d/%Y %H:%M')
    end
    
    actions
  end

  # Show page
  show do
    attributes_table do
      row :id
      row :customer_subscription do |transaction|
        link_to "Subscription ##{transaction.customer_subscription.id}", 
                admin_customer_subscription_path(transaction.customer_subscription)
      end
      row :business do |transaction|
        link_to transaction.business.name, admin_business_path(transaction.business)
      end
      row :customer do |transaction|
        div do
          strong transaction.tenant_customer.name
        end
        div do
          mail_to transaction.tenant_customer.email
        end
        div do
          link_to "View User", admin_user_path(transaction.tenant_customer.user) if transaction.tenant_customer.user
        end
      end
      row :transaction_type do |transaction|
        status_tag transaction.transaction_type, class: transaction_type_class(transaction.transaction_type)
      end
      row :status do |transaction|
        status_tag transaction.status, class: transaction_status_class(transaction.status)
      end
      row :amount do |transaction|
        number_to_currency(transaction.amount)
      end
      row :processed_date
      row :failure_reason
      row :notes
      row :stripe_invoice_id do |transaction|
        if transaction.stripe_invoice_id.present?
          div do
            code transaction.stripe_invoice_id
          end
          div do
            link_to "View in Stripe", "https://dashboard.stripe.com/invoices/#{transaction.stripe_invoice_id}", 
                    target: '_blank', class: 'button'
          end
        else
          span "No Stripe invoice", class: 'empty'
        end
      end
      row :stripe_payment_intent_id do |transaction|
        if transaction.stripe_payment_intent_id.present?
          div do
            code transaction.stripe_payment_intent_id
          end
          div do
            link_to "View in Stripe", "https://dashboard.stripe.com/payments/#{transaction.stripe_payment_intent_id}", 
                    target: '_blank', class: 'button'
          end
        else
          span "No Stripe payment intent", class: 'empty'
        end
      end
      row :created_at
      row :updated_at
    end

    # Related subscription details
    panel "Subscription Details" do
      subscription = transaction.customer_subscription
      attributes_table_for subscription do
        row :subscription_type
        row :item do
          if subscription.product
            link_to subscription.product.name, admin_product_path(subscription.product)
          elsif subscription.service
            link_to subscription.service.name, admin_service_path(subscription.service)
          end
        end
        row :frequency
        row :quantity
        row :subscription_price do
          number_to_currency(subscription.subscription_price)
        end
        row :status do
          status_tag subscription.status
        end
        row :next_billing_date
      end
    end

    active_admin_comments
  end

  # Form for editing (limited fields)
  form do |f|
    f.inputs "Transaction Details" do
      f.input :customer_subscription, as: :select, 
              collection: CustomerSubscription.joins(:business).order('businesses.name').map { |cs| 
                ["#{cs.business.name} - Subscription ##{cs.id}", cs.id] 
              }, include_blank: false
      f.input :transaction_type, as: :select, collection: SubscriptionTransaction.transaction_types, include_blank: false
      f.input :status, as: :select, collection: SubscriptionTransaction.statuses, include_blank: false
      f.input :amount
      f.input :processed_date, as: :date_time_picker
      f.input :failure_reason
      f.input :notes
    end

    f.inputs "Stripe Information" do
      f.input :stripe_invoice_id
      f.input :stripe_payment_intent_id
    end

    f.actions
  end

  # CSV export
  csv do
    column :id
    column :subscription_id do |transaction|
      transaction.customer_subscription.id
    end
    column :business_name do |transaction|
      transaction.business.name
    end
    column :customer_email do |transaction|
      transaction.tenant_customer.email
    end
    column :transaction_type
    column :status
    column :amount
    column :processed_date
    column :failure_reason
    column :stripe_invoice_id
    column :stripe_payment_intent_id
    column :created_at
  end

  # Helper methods
  controller do
    private

    def transaction_type_class(type)
      case type.to_s
      when 'billing', 'signup' then 'ok'
      when 'failed_payment' then 'error'
      when 'refund' then 'warning'
      when 'cancellation' then 'error'
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
 
 
 
 