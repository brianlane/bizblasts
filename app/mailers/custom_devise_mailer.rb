class CustomDeviseMailer < Devise::Passwordless::Mailer
  # Override confirmation_instructions to use different templates based on user role
  def confirmation_instructions(record, token, opts = {})
    @token = token
    @resource = record
    
    # Determine template path based on user role
    template_path = if record.respond_to?(:client?) && record.client?
      'devise/mailer/client'
    else
      'devise/mailer/business' 
    end
    
    devise_mail(record, :confirmation_instructions, opts.merge(template_path: template_path))
  end
  
  # Override other email methods if needed to differentiate by user type
  def reset_password_instructions(record, token, opts = {})
    @token = token
    @resource = record
    
    template_path = if record.respond_to?(:client?) && record.client?
      'devise/mailer/client'
    else
      'devise/mailer/business'
    end
    
    devise_mail(record, :reset_password_instructions, opts.merge(template_path: template_path))
  end
  
  def email_changed(record, opts = {})
    @resource = record
    
    template_path = if record.respond_to?(:client?) && record.client?
      'devise/mailer/client'
    else
      'devise/mailer/business'
    end
    
    devise_mail(record, :email_changed, opts.merge(template_path: template_path))
  end
  
  def password_change(record, opts = {})
    @resource = record
    
    template_path = if record.respond_to?(:client?) && record.client?
      'devise/mailer/client'
    else
      'devise/mailer/business'
    end
    
    devise_mail(record, :password_change, opts.merge(template_path: template_path))
  end
end 