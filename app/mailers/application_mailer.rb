# frozen_string_literal: true

# Base mailer class for all application mailers
# Sets default from address and layout
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end
