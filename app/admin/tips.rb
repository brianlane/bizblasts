ActiveAdmin.register Tip do
  permit_params :business_id, :booking_id, :tenant_customer_id, :amount, :status

  # Define explicit filters
  filter :business
  filter :booking
  filter :tenant_customer
  filter :amount
  filter :status, as: :select, collection: Tip.statuses.keys.map { |k| [k.humanize, k] }
  filter :paid_at
  filter :created_at
  filter :updated_at

  index do
    selectable_column
    id_column
    column :business do |tip|
      link_to tip.business.name, admin_business_path(tip.business) if tip.business
    end
    column :booking do |tip|
      link_to "Booking ##{tip.booking.id}", admin_booking_path(tip.booking) if tip.booking
    end
    column :tenant_customer do |tip|
      tip.tenant_customer&.full_name
    end
    column :amount do |tip|
      number_to_currency(tip.amount)
    end
    column :business_amount do |tip|
      number_to_currency(tip.business_amount) if tip.business_amount
    end
    column :status do |tip|
      status_tag tip.status
    end
    column :paid_at
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :business do |tip|
        link_to tip.business.name, admin_business_path(tip.business)
      end
      row :booking do |tip|
        link_to "Booking ##{tip.booking.id}", admin_booking_path(tip.booking)
      end
      row :tenant_customer do |tip|
        tip.tenant_customer&.full_name
      end
      row :amount do |tip|
        number_to_currency(tip.amount)
      end
      row :stripe_fee_amount do |tip|
        number_to_currency(tip.stripe_fee_amount) if tip.stripe_fee_amount
      end
      row :platform_fee_amount do |tip|
        number_to_currency(tip.platform_fee_amount) if tip.platform_fee_amount
      end
      row :business_amount do |tip|
        number_to_currency(tip.business_amount) if tip.business_amount
      end
      row :status do |tip|
        status_tag tip.status
      end
      row :stripe_payment_intent_id
      row :stripe_charge_id
      row :paid_at
      row :failure_reason if resource.failed?
      row :created_at
      row :updated_at
    end

    panel "Fee Breakdown" do
      table_for [resource] do
        column "Tip Amount" do |tip|
          number_to_currency(tip.amount)
        end
        column "Stripe Fee" do |tip|
          number_to_currency(tip.stripe_fee_amount || 0)
        end
        column "Platform Fee" do |tip|
          number_to_currency(tip.platform_fee_amount || 0)
        end
        column "Total Fees" do |tip|
          number_to_currency(tip.total_fees)
        end
        column "Business Receives" do |tip|
          number_to_currency(tip.business_amount || tip.net_business_amount)
        end
      end
    end

    active_admin_comments
  end

  form do |f|
    f.inputs "Tip Details" do
      f.input :business
      f.input :booking, collection: Booking.includes(:business, :tenant_customer).order(created_at: :desc).limit(100)
      f.input :tenant_customer
      f.input :amount
      f.input :status, as: :select, collection: Tip.statuses.keys.map { |k| [k.humanize, k] }
    end
    f.actions
  end
end