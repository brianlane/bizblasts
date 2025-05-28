class BusinessMailer < ApplicationMailer
  # Send domain request notification to premium business users after email confirmation
  def domain_request_notification(user)
    @user = user
    @business = user.business
    @domain_requested = @business.hostname if @business.host_type_custom_domain?
    
    mail(
      to: @user.email,
      subject: "Custom Domain Request Received - #{@business.name}"
    )
  end
end 