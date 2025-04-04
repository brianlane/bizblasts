ActiveAdmin.register Appointment do

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
  filter :status, as: :select, collection: Appointment.statuses
  filter :start_time
  filter :price
  filter :paid
  
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
    column :price do |appointment|
      number_to_currency(appointment.price) if appointment.price
    end
    column :paid
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
      row :price do |appointment|
        number_to_currency(appointment.price) if appointment.price
      end
      row :paid
      row :notes
      row :metadata
      row :stripe_payment_intent_id
      row :stripe_customer_id
      row :cancelled_at
      row :cancellation_reason
      row :created_at
      row :updated_at
    end
  end
  
  form do |f|
    f.inputs do
      f.input :business
      f.input :tenant_customer, collection: TenantCustomer.where(business: f.object.business || ActsAsTenant.current_tenant)
      f.input :staff_member, collection: StaffMember.where(business: f.object.business || ActsAsTenant.current_tenant)
      f.input :service, collection: Service.where(business: f.object.business || ActsAsTenant.current_tenant)
      f.input :start_time
      f.input :end_time
      f.input :status, as: :select, collection: Appointment.statuses.keys.map { |s| [s.titleize, s] }
      f.input :price
      f.input :paid
      f.input :notes
      f.input :cancelled_at
      f.input :cancellation_reason
    end
    f.actions
  end
end
