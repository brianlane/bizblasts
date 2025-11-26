class Client::EstimatesController < ApplicationController
  before_action :authenticate_user!
  layout 'client'

  def index
    # Client users can be associated with multiple businesses, so we bypass
    # tenant scoping and let the policy scope filter estimates appropriately
    @estimates = ActsAsTenant.without_tenant do
      policy_scope(Estimate).order(created_at: :desc)
    end
  end

  def show
    # Bypass tenant scoping for the find, then authorize access
    @estimate = ActsAsTenant.without_tenant do
      authorize(Estimate.find(params[:id]))
    end
  end
end 