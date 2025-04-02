ActiveAdmin.register SoftwareSubscription do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  # permit_params :company_id, :software_product_id, :status, :started_at, :ends_at, :license_key, :subscription_type, :subscription_details, :auto_renew, :payment_status, :stripe_subscription_id, :stripe_customer_id, :usage_metrics, :notes
  #
  # or
  #
  # permit_params do
  #   permitted = [:company_id, :software_product_id, :status, :started_at, :ends_at, :license_key, :subscription_type, :subscription_details, :auto_renew, :payment_status, :stripe_subscription_id, :stripe_customer_id, :usage_metrics, :notes]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end
  
end
