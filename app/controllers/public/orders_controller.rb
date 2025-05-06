module Public
  class OrdersController < ::OrdersController
    before_action :set_tenant
  end
end