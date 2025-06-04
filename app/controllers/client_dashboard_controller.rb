class ClientDashboardController < ApplicationController
  def index
    if current_user.client?
      # Fetch recent bookings across all businesses (last 7 days)
      @recent_bookings = fetch_recent_bookings.limit(5)
      
      # Fetch upcoming appointments (next 7 days)
      @upcoming_appointments = fetch_upcoming_appointments.limit(5)
      
      # Fetch recent transactions/orders (last 30 days)
      @recent_transactions = fetch_recent_transactions.limit(5)
      
      # Get cart status and items count
      @cart_items_count = session[:cart]&.values&.sum || 0
      
      # Get favorite/frequent businesses (based on booking history)
      @frequent_businesses = fetch_frequent_businesses.limit(3)
      
      # Account activity summary
      @activity_summary = calculate_activity_summary
    else
      redirect_to root_path, alert: "Access denied."
    end
  end

  private

  def fetch_recent_bookings
    # Get bookings from all tenant customers associated with current user's email
    tenant_customer_ids = TenantCustomer.where(email: current_user.email).pluck(:id)
    Booking.joins(:tenant_customer)
           .where(tenant_customers: { id: tenant_customer_ids })
           .where(start_time: 7.days.ago..Time.current)
           .includes(:service, :business, :staff_member)
           .order(start_time: :desc)
  end

  def fetch_upcoming_appointments
    tenant_customer_ids = TenantCustomer.where(email: current_user.email).pluck(:id)
    Booking.joins(:tenant_customer)
           .where(tenant_customers: { id: tenant_customer_ids })
           .where(start_time: Time.current..7.days.from_now)
           .includes(:service, :business, :staff_member)
           .order(start_time: :asc)
  end

  def fetch_recent_transactions
    # Get recent orders and invoices
    tenant_customer_ids = TenantCustomer.where(email: current_user.email).pluck(:id)
    Order.joins(:tenant_customer)
         .where(tenant_customers: { id: tenant_customer_ids })
         .where(created_at: 30.days.ago..Time.current)
         .includes(:business, :line_items)
         .order(created_at: :desc)
  end

  def fetch_frequent_businesses
    # Find businesses with most bookings/orders for this user
    tenant_customer_ids = TenantCustomer.where(email: current_user.email).pluck(:id)
    
    business_counts = {}
    
    # Count bookings per business
    Booking.joins(:tenant_customer, :business)
           .where(tenant_customers: { id: tenant_customer_ids })
           .where(start_time: 90.days.ago..Time.current)
           .group(:business_id)
           .count
           .each { |business_id, count| business_counts[business_id] = count }
    
    # Count orders per business
    Order.joins(:tenant_customer, :business)
         .where(tenant_customers: { id: tenant_customer_ids })
         .where(created_at: 90.days.ago..Time.current)
         .group(:business_id)
         .count
         .each { |business_id, count| business_counts[business_id] = (business_counts[business_id] || 0) + count }
    
    # Get top businesses
    top_business_ids = business_counts.sort_by(&:last).reverse.map(&:first)
    Business.where(id: top_business_ids).limit(3)
  end

  def calculate_activity_summary
    tenant_customer_ids = TenantCustomer.where(email: current_user.email).pluck(:id)
    
    {
      total_bookings: Booking.joins(:tenant_customer).where(tenant_customers: { id: tenant_customer_ids }).count,
      bookings_this_month: Booking.joins(:tenant_customer).where(tenant_customers: { id: tenant_customer_ids }).where(start_time: 1.month.ago..Time.current).count,
      total_orders: Order.joins(:tenant_customer).where(tenant_customers: { id: tenant_customer_ids }).count,
      orders_this_month: Order.joins(:tenant_customer).where(tenant_customers: { id: tenant_customer_ids }).where(created_at: 1.month.ago..Time.current).count,
      businesses_visited: Business.joins(:bookings).joins('JOIN tenant_customers ON bookings.tenant_customer_id = tenant_customers.id').where(tenant_customers: { id: tenant_customer_ids }).distinct.count
    }
  end
end 