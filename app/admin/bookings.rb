ActiveAdmin.register Booking do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :business_id, :service_id, :staff_member_id, :tenant_customer_id, 
                :start_time, :end_time, :status, :price, :notes, :metadata, 
                :stripe_payment_intent_id, :stripe_customer_id, :paid, 
                :cancelled_at, :cancellation_reason
  
  scope :all
  scope :upcoming
  scope :today
  scope :past
  
  filter :business
  filter :staff_member
  filter :tenant_customer
  filter :service
  filter :status, as: :select, collection: Booking.statuses
  filter :start_time
  filter :amount
  filter :promotion
  
  index do
    selectable_column
    id_column
    column :business
    column :tenant_customer
    column :staff_member
    column :service
    column :start_time
    column :end_time
    column :status
    column :amount do |booking|
      number_to_currency(booking.amount) if booking.amount
    end
    column :promotion
    actions
  end
  
  show do
    attributes_table do
      row :id
      row :business
      row :tenant_customer
      row :staff_member
      row :service
      row :start_time
      row :end_time
      row :status
      row :original_amount do |booking|
        number_to_currency(booking.original_amount) if booking.original_amount
      end
      row :discount_amount do |booking|
        number_to_currency(booking.discount_amount) if booking.discount_amount
      end
      row :amount do |booking|
        number_to_currency(booking.amount) if booking.amount
      end
      row :notes
      row :metadata
      row :stripe_payment_intent_id
      row :stripe_customer_id
      row :promotion
      row :cancelled_at
      row :cancellation_reason
      row :created_at
      row :updated_at
      row :invoice do |booking|
        link_to booking.invoice.invoice_number, admin_invoice_path(booking.invoice) if booking.invoice
      end
    end
  end
  
  form do |f|
    f.inputs do
      f.input :business
      current_business = f.object.business || ActsAsTenant.current_tenant
      f.input :tenant_customer, collection: TenantCustomer.where(business: current_business)
      f.input :staff_member, collection: StaffMember.where(business: current_business)
      f.input :service, collection: Service.where(business: current_business)
      f.input :start_time
      f.input :end_time
      f.input :status, as: :select, collection: Booking.statuses.keys.map { |s| [s.titleize, s] }
      f.input :notes
      f.input :promotion, collection: Promotion.where(business: current_business)
      f.input :cancellation_reason
    end
    f.actions
  end
end
