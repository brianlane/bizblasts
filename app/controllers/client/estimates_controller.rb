class Client::EstimatesController < ApplicationController
  before_action :authenticate_user!
  layout 'client'

  def index
    @estimates = policy_scope(Estimate).order(created_at: :desc)
  end

  def show
    @estimate = authorize(Estimate.find(params[:id]))
  end
end 