# frozen_string_literal: true

# Controller for the main business dashboard.
class BusinessManager::DashboardController < BusinessManager::BaseController
  def index
    # The @current_business instance variable is set by the authorize_business_user! in BaseController
    # Fetch data needed for the dashboard view, e.g.:
    # @upcoming_bookings = @current_business.bookings.upcoming.limit(5)
    # @recent_activity = ActivityLog.for_business(@current_business).recent(10)
    # For now, just render the view.
  end
end 