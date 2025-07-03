ActiveAdmin.register Payment do
  permit_params :business_id, :invoice_id, :order_id, :tenant_customer_id, :amount, 
                :payment_method, :status, :completed_at, :refunded_at

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
    column :completed_at
    column :refunded_at
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
      f.input :completed_at, as: :datepicker
      f.input :refunded_at, as: :datepicker
    end
    f.actions
  end
end 