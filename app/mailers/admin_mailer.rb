# frozen_string_literal: true

# Mailer for admin notifications
class AdminMailer < ApplicationMailer
  # Send notification to admin when a new business registers
  def new_business_registration(business, owner_user)
    @business = business
    @owner_user = owner_user
    @business_url = business_admin_url(@business)
    @owner_url = admin_user_url(@owner_user)
    
    mail(
      to: ENV['ADMIN_EMAIL'],
      subject: "New Business Registration: #{@business.name}",
      reply_to: ENV['SUPPORT_EMAIL']
    )
  end

  private

  def business_admin_url(business)
    Rails.application.routes.url_helpers.admin_business_url(
      business,
      host: admin_host,
      protocol: Rails.env.production? ? 'https' : 'http'
    )
  end

  def admin_user_url(user)
    Rails.application.routes.url_helpers.admin_user_url(
      user,
      host: admin_host,
      protocol: Rails.env.production? ? 'https' : 'http'
    )
  end

  def admin_host
    if Rails.env.production?
      'www.bizblasts.com'
    elsif Rails.env.development?
      'localhost:3000'
    else
      'test.host'
    end
  end
end