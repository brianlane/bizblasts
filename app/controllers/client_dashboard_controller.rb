class ClientDashboardController < ApplicationController
  helper ClientDocumentsHelper
  before_action :authenticate_user!
  before_action :ensure_client_user
  before_action :set_tenant_customer_ids
  
  def index
    # Fetch recent bookings across all businesses (last 7 days)
    @recent_bookings = fetch_recent_bookings.limit(5)
    
    # Fetch upcoming appointments (next 7 days)
    @upcoming_appointments = fetch_upcoming_appointments.limit(5)

    # Fetch upcoming rentals (next 30 days)
    @upcoming_rental_bookings = fetch_upcoming_rental_bookings.limit(5)
    
    # Fetch recent estimates
    @recent_estimates = fetch_recent_estimates.limit(5)

    # Fetch recent client documents/waivers
    @recent_documents = fetch_recent_client_documents.limit(5)
    
    # Fetch recent transactions/orders (last 30 days)
    @recent_transactions = fetch_recent_transactions.limit(5)
    
    # Get cart status and items count
    @cart_items_count = session[:cart]&.values&.sum || 0
    
    # Get favorite/frequent businesses (based on booking history)
    @frequent_businesses = fetch_frequent_businesses.limit(3)
    
    # Account activity summary
    @activity_summary = calculate_activity_summary
  end

  private

  def ensure_client_user
    unless current_user&.client?
      redirect_to root_path, alert: "Access denied."
    end
  end

  def set_tenant_customer_ids
    @tenant_customer_ids ||= Rails.cache.fetch("user_#{current_user.id}_tenant_customers", expires_in: 15.minutes) do
      TenantCustomer.where(email: current_user.email).pluck(:id)
    end
  end

  def fetch_recent_bookings
    # Use cached tenant customer IDs
    Booking.joins(:tenant_customer)
           .where(tenant_customers: { id: @tenant_customer_ids })
           .where(start_time: 7.days.ago..Time.current)
           .includes(:service, :business, :staff_member)
           .order(start_time: :desc)
  end

  def fetch_upcoming_appointments
    Booking.joins(:tenant_customer)
           .where(tenant_customers: { id: @tenant_customer_ids })
           .where(start_time: Time.current..7.days.from_now)
           .includes(:service, :business, :staff_member)
           .order(start_time: :asc)
  end

  def fetch_recent_transactions
    # Get recent orders and invoices
    Order.joins(:tenant_customer)
         .where(tenant_customers: { id: @tenant_customer_ids })
         .where(created_at: 30.days.ago..Time.current)
         .includes(:business, :line_items)
         .order(created_at: :desc)
  end

  def fetch_frequent_businesses
    # Find businesses with most bookings/orders for this user
    business_counts = {}
    
    # Count bookings per business
    Booking.joins(:tenant_customer, :business)
           .where(tenant_customers: { id: @tenant_customer_ids })
           .where(start_time: 90.days.ago..Time.current)
           .group(:business_id)
           .count
           .each { |business_id, count| business_counts[business_id] = count }
    
    # Count orders per business
    Order.joins(:tenant_customer, :business)
         .where(tenant_customers: { id: @tenant_customer_ids })
         .where(created_at: 90.days.ago..Time.current)
         .group(:business_id)
         .count
         .each { |business_id, count| business_counts[business_id] = (business_counts[business_id] || 0) + count }
    
    # Get top businesses
    top_business_ids = business_counts.sort_by(&:last).reverse.map(&:first)
    Business.where(id: top_business_ids).limit(3)
  end

  def calculate_activity_summary
    {
      total_bookings: Booking.joins(:tenant_customer).where(tenant_customers: { id: @tenant_customer_ids }).count,
      bookings_this_month: Booking.joins(:tenant_customer).where(tenant_customers: { id: @tenant_customer_ids }).where(start_time: 1.month.ago..Time.current).count,
      total_orders: Order.joins(:tenant_customer).where(tenant_customers: { id: @tenant_customer_ids }).count,
      orders_this_month: Order.joins(:tenant_customer).where(tenant_customers: { id: @tenant_customer_ids }).where(created_at: 1.month.ago..Time.current).count,
      businesses_visited: Business.joins(:bookings).joins('JOIN tenant_customers ON bookings.tenant_customer_id = tenant_customers.id').where(tenant_customers: { id: @tenant_customer_ids }).distinct.count
    }
  end

  def fetch_upcoming_rental_bookings
    ActsAsTenant.without_tenant do
      RentalBooking.joins(:tenant_customer)
                   .where(tenant_customers: { id: @tenant_customer_ids })
                   .where('start_time >= ?', Time.current)
                   .where.not(status: 'cancelled')
                   .includes(:product, :business)
                   .order(start_time: :asc)
    end
  end

  def fetch_recent_estimates
    ActsAsTenant.without_tenant do
      Estimate.joins(:tenant_customer)
              .where(tenant_customers: { id: @tenant_customer_ids })
              .order(created_at: :desc)
    end
  end

  def fetch_recent_client_documents
    ActsAsTenant.without_tenant do
      ClientDocument
        .where(tenant_customer_id: @tenant_customer_ids)
        .order(updated_at: :desc)
    end
  end
end 