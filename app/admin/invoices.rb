ActiveAdmin.register Invoice do
  permit_params :tenant_customer_id, :booking_id, :order_id, :promotion_id, 
                :shipping_method_id, :tax_rate_id, :business_id, :amount, 
                :total_amount, :due_date, :status, :invoice_number, 
                :original_amount, :discount_amount, :tip_amount

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters

  index do
    selectable_column
    id_column
    column :invoice_number
    column :business
    column :tenant_customer
    column :booking
    column :order
    column :amount do |invoice|
      number_to_currency(invoice.amount)
    end
    column :total_amount do |invoice|
      number_to_currency(invoice.total_amount)
    end
    column :due_date
    column :status do |invoice|
      status_tag invoice.status
    end
    actions
  end

  show do
    attributes_table do
      row :id
      row :invoice_number
      row :business
      row :tenant_customer
      row :booking
      row :order
      row :promotion
      row :shipping_method
      row :tax_rate
      row :original_amount do |invoice|
        number_to_currency(invoice.original_amount) if invoice.original_amount
      end
      row :discount_amount do |invoice|
        number_to_currency(invoice.discount_amount) if invoice.discount_amount
      end
      row :amount do |invoice|
        number_to_currency(invoice.amount)
      end
      row :tip_amount do |invoice|
        number_to_currency(invoice.tip_amount) if invoice.tip_amount
      end
      row :total_amount do |invoice|
        number_to_currency(invoice.total_amount)
      end
      row :due_date
      row :status do |invoice|
        status_tag invoice.status
      end
      row :stripe_invoice_id
      row :created_at
      row :updated_at
    end

    panel "Line Items" do
      table_for invoice.line_items do
        column :product do |item|
          item.product&.name
        end
        column :quantity
        column :price do |item|
          number_to_currency(item.price)
        end
        column :total_amount do |item|
          number_to_currency(item.total_amount)
        end
      end
    end

    panel "Payments" do
      table_for invoice.payments do
        column :id do |payment|
          link_to payment.id, admin_payment_path(payment)
        end
        column :amount do |payment|
          number_to_currency(payment.amount)
        end
        column :status do |payment|
          status_tag payment.status
        end
        column :created_at
      end
    end
  end

  form do |f|
    f.inputs 'Invoice Details' do
      f.input :business
      f.input :tenant_customer
      f.input :booking
      f.input :order
      f.input :promotion
      f.input :shipping_method
      f.input :tax_rate
      f.input :status, as: :select, collection: Invoice.statuses.keys
      f.input :due_date, as: :datepicker
      f.input :original_amount
      f.input :discount_amount
      f.input :amount
      f.input :tip_amount
      f.input :total_amount
    end
    f.actions
  end
end 