ActiveAdmin.register Payment do
  permit_params :business_id, :invoice_id, :order_id, :tenant_customer_id, :amount,
                :payment_method, :status, :paid_at

  # Define explicit filters to avoid ransack errors from auto-generated
  # default filters (a new column missing from ransackable_attributes would
  # otherwise 500 the whole index page).
  filter :business
  filter :invoice_id
  filter :order_id
  filter :tenant_customer_id
  filter :amount
  filter :payment_method, as: :select, collection: Payment.payment_methods.keys.map { |k| [k.humanize, k] }
  filter :status, as: :select, collection: Payment.statuses.keys.map { |k| [k.humanize, k] }
  filter :stripe_payment_intent_id
  filter :paid_at
  filter :created_at
  filter :updated_at

  index do
    selectable_column
    id_column
    column :business
    column :invoice
    column :order
    column :tenant_customer
    column :amount do |payment|
      number_to_currency(payment.amount)
    end
    column :payment_method
    column :status do |payment|
      status_tag payment.status
    end
    column :paid_at
    column :refunded_amount do |payment|
      number_to_currency(payment.refunded_amount) if payment.refunded_amount&.positive?
    end
    actions
  end

  form do |f|
    f.inputs 'Payment Details' do
      f.input :business
      f.input :invoice
      f.input :order
      f.input :tenant_customer
      f.input :amount
      f.input :payment_method, as: :select, collection: Payment.payment_methods.keys
      f.input :status, as: :select, collection: Payment.statuses.keys
      f.input :paid_at, as: :datepicker
    end
    f.actions
  end
end
