ActiveAdmin.register Appointment do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :company_id, :service_id, :service_provider_id, :client_name, :client_email, :client_phone, :start_time, :end_time, :status, :price, :notes, :metadata, :stripe_payment_intent_id, :stripe_customer_id, :paid, :cancelled_at, :cancellation_reason, :customer_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:company_id, :service_id, :service_provider_id, :client_name, :client_email, :client_phone, :start_time, :end_time, :status, :price, :notes, :metadata, :stripe_payment_intent_id, :stripe_customer_id, :paid, :cancelled_at, :cancellation_reason, :customer_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end
  
end
