module Admin
  class ApplicationController < ApplicationController
    before_action :authenticate_admin_user!
    
    protected
    
    def active_admin_config
      ActiveAdmin.application.namespace(:admin).resources.detect { |resource| resource.controller_name == controller_name }
    end
  end
end 