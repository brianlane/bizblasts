class LoyaltyPointsService
  class << self
    def award_points(customer:, points:, description:, related_record: nil)
      return 0 unless customer.business.loyalty_program_active?
      return 0 unless points > 0
      
      transaction = customer.loyalty_transactions.create!(
        business: customer.business,
        transaction_type: 'earned',
        points_amount: points,
        description: description,
        related_booking: related_record.is_a?(Booking) ? related_record : nil,
        related_order: related_record.is_a?(Order) ? related_record : nil,
        related_referral: related_record.is_a?(Referral) ? related_record : nil
      )
      
      points
    end
    
    def award_booking_points(booking)
      return 0 unless booking.business.loyalty_program_active?
      
      customer = booking.tenant_customer
      return 0 unless customer
      
      # Only award points if customer has an associated user account (not a guest)
      return 0 unless User.exists?(email: customer.email)
      
      # Check if points already awarded for this booking
      existing_transaction = LoyaltyTransaction.where(related_booking: booking).first
      return 0 if existing_transaction
      
      business = booking.business
      # Use original amount if available (before any discounts), otherwise use current amount
      amount_for_points = booking.original_amount.present? ? booking.original_amount : booking.amount
      points = business.calculate_loyalty_points(
        amount_for_points,
        service: booking.service
      )
      
      return 0 unless points > 0
      
      award_points(
        customer: customer,
        points: points,
        description: "Points earned from booking ##{booking.id}",
        related_record: booking
      )
    end
    
    def award_order_points(order)
      return 0 unless order.business.loyalty_program_active?
      
      customer = order.tenant_customer
      return 0 unless customer
      
      # Only award points if customer has an associated user account (not a guest)
      return 0 unless User.exists?(email: customer.email)
      
      # Check if points already awarded for this order
      existing_transaction = LoyaltyTransaction.where(related_order: order).first
      return 0 if existing_transaction
      
      business = order.business
      total_points = 0
      
      # Points for order total (only if amount > 0)
      if order.total_amount.present? && order.total_amount > 0
        total_points += business.calculate_loyalty_points(order.total_amount)
      end
      
      # Points for individual products (only if line item amount > 0)
      order.line_items.includes(:product_variant).each do |line_item|
        if line_item.product_variant && line_item.total_amount.present? && line_item.total_amount > 0
          product_points = business.calculate_loyalty_points(
            line_item.total_amount,
            product: line_item.product_variant.product
          )
          total_points += product_points
        end
      end
      
      return 0 unless total_points > 0
      
      award_points(
        customer: customer,
        points: total_points,
        description: "Points earned from order ##{order.order_number}",
        related_record: order
      )
    end
    
    def redeem_points_for_discount(customer:, points:, description: nil)
      return { success: false, error: 'Insufficient points' } unless customer.can_redeem_points?(points)
      return { success: false, error: 'Invalid points amount' } unless points > 0
      return { success: false, error: 'Points must be multiple of 100' } unless points % 100 == 0
      return { success: false, error: 'Loyalty program not active' } unless customer.business.loyalty_program_active?
      
      business = customer.business
      
      begin
        ActiveRecord::Base.transaction do
          # Create Stripe coupon
          stripe_coupon_id = nil
          discount_amount = (points / 10) # 10 points = $1
          
          # Always try to create Stripe coupon (will be mocked in tests)
          stripe_coupon = Stripe::Coupon.create({
            amount_off: (discount_amount * 100).to_i, # Stripe expects cents
            currency: 'usd',
            duration: 'once',
            name: "Loyalty Points Redemption - #{points} points"
          })
          stripe_coupon_id = stripe_coupon.id
          
          # Create discount code
          discount_code = business.discount_codes.create!(
            code: generate_loyalty_discount_code,
            discount_type: 'fixed_amount',
            discount_value: discount_amount,
            used_by_customer: customer,
            tenant_customer: customer,
            single_use: true,
            active: true,
            points_redeemed: points,
            stripe_coupon_id: stripe_coupon_id
          )
          
          # Create redemption transaction
          customer.loyalty_transactions.create!(
            business: business,
            transaction_type: 'redeemed',
            points_amount: -points,
            description: description || "Redeemed #{points} points for $#{discount_amount} discount code"
          )
          
          { 
            success: true, 
            discount_code: discount_code.code,
            discount_amount: discount_amount
          }
        end
      rescue Stripe::StripeError => e
        { success: false, error: "Stripe error: #{e.message}" }
      rescue => e
        { success: false, error: "Error creating discount code: #{e.message}" }
      end
    end
    
    private
    
    def generate_loyalty_discount_code
      loop do
        code = "LOYALTY-#{SecureRandom.alphanumeric(6).upcase}"
        break code unless DiscountCode.exists?(code: code)
      end
    end
    
    public
    
    def calculate_points_for_amount(business, amount, service: nil, product: nil)
      business.calculate_loyalty_points(amount, service: service, product: product)
    end
    
    def get_customer_summary(customer)
      {
        current_points: customer.current_loyalty_points,
        total_earned: customer.loyalty_points_earned,
        total_redeemed: customer.loyalty_points_redeemed,
        available_for_redemption: (customer.current_loyalty_points / 100) * 100, # Only multiples of 100
        next_reward_threshold: ((customer.current_loyalty_points / 100) + 1) * 100,
        points_to_next_reward: ((customer.current_loyalty_points / 100) + 1) * 100 - customer.current_loyalty_points
      }
    end
    
    def get_redemption_options(customer)
      current_points = customer.current_loyalty_points
      options = []
      
      # Generate redemption options in $10 increments
      (1..10).each do |multiplier|
        points_needed = multiplier * 100
        break if points_needed > current_points
        
        options << {
          points: points_needed,
          discount_amount: multiplier * 10,
          description: "$#{multiplier * 10} off your next purchase"
        }
      end
      
      options
    end
    
    # Method expected by specs - delegates to redeem_points_for_discount
    def redeem_points(customer, points, description)
      redeem_points_for_discount(customer: customer, points: points, description: description)
    end
    
    # Method expected by specs
    def calculate_customer_balance(customer)
      customer.current_loyalty_points
    end
    
    # Method expected by specs
    def expire_points
      # Find all expired points that haven't been processed
      expired_transactions = LoyaltyTransaction.earned.where('expires_at < ?', Time.current)
      
      expired_transactions.each do |transaction|
        next unless transaction.points_amount > 0
        
        # Check if already expired
        existing_expiration = LoyaltyTransaction.expired
                                               .where(tenant_customer: transaction.tenant_customer)
                                               .where('description LIKE ?', "%transaction ##{transaction.id}%")
                                               .exists?
        next if existing_expiration
        
        transaction.tenant_customer.loyalty_transactions.create!(
          business: transaction.business,
          transaction_type: 'expired',
          points_amount: -transaction.points_amount,
          description: "Points expired from transaction ##{transaction.id}"
        )
      end
    end
    
    # Method expected by specs  
    def award_referral_points(referral)
      return 0 unless referral.business.loyalty_program_active?
      return 0 unless referral.qualified?
      
      # Check if points already awarded
      existing_transaction = LoyaltyTransaction.where(related_referral: referral).first
      return 0 if existing_transaction
      
      # Get referrer as customer
      referrer_customer = TenantCustomer.find_by(email: referral.referrer.email, business: referral.business)
      return 0 unless referrer_customer
      
      # Award referral points (default 100 points)
      points = 100
      award_points(
        customer: referrer_customer,
        points: points,
        description: "Referral reward for referring #{referral.referred_tenant_customer.email}",
        related_record: referral
      )
    end
  end
end 