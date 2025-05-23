ActiveAdmin.register Booking do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :business_id, :service_id, :staff_member_id, :tenant_customer_id, 
                :start_time, :end_time, :status, :price, :notes, :metadata, 
                :stripe_payment_intent_id, :stripe_customer_id, :paid, 
                :cancelled_at, :cancellation_reason, :quantity
  
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
    column :business do |booking|
      if booking.business&.id
        link_to booking.business.name, admin_business_path(booking.business.id)
      elsif booking.business
        booking.business.name || status_tag("Invalid Business")
      else
        status_tag("None")
      end
    end
    column :tenant_customer
    column :staff_member
    column :service
    column :start_time
    column :end_time
    column :status
    column :amount do |booking|
      number_to_currency(booking.amount) if booking.amount
    end
    column :quantity
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
      row :quantity
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
      
      # Define variable for business
      current_business = if f.object.business_id
        Business.find_by(id: f.object.business_id)
      elsif ActsAsTenant.current_tenant
        ActsAsTenant.current_tenant
      end
      
      # Get collections based on the current business
      tenant_customers = current_business ? TenantCustomer.where(business: current_business) : TenantCustomer.none
      staff_members = current_business ? StaffMember.where(business: current_business) : StaffMember.none
      services = current_business ? Service.where(business: current_business) : Service.none
      promotions = current_business ? Promotion.where(business: current_business) : Promotion.none
      
      f.input :tenant_customer, collection: tenant_customers
      f.input :staff_member, collection: staff_members, selected: f.object.staff_member_id
      f.input :service, collection: services, selected: f.object.service_id
      f.input :quantity
      f.input :start_time
      f.input :end_time
      f.input :status, as: :select, collection: Booking.statuses.keys.map { |s| [s.titleize, s] }
      f.input :notes
      f.input :promotion, collection: promotions
      f.input :cancellation_reason
    end
    f.actions
  end
end
