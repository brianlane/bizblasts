class PlatformLoyaltyService
  REFERRAL_REWARD_POINTS = 500
  POINTS_TO_DOLLAR_RATE = 10 # 100 points = $10
  MAX_DISCOUNT_POINTS = 1000     # Maximum points that can be redeemed at once
  
  class << self
    # Configure Stripe API key (called by tests)
    def configure_stripe_api_key
      # This method is used by tests to mock Stripe configuration
      # In production, Stripe is configured in initializers
    end
    # Track when a business signs up with a referral code
    def track_platform_referral_signup(new_business, referral_code)
      return nil if referral_code.blank?
      
      # Find referring business by their platform referral code
      referring_business = Business.find_by(platform_referral_code: referral_code)
      return nil unless referring_business
      
      # Prevent self-referral
      return nil if referring_business.id == new_business.id
      
      # Create platform referral record
      platform_referral = PlatformReferral.create!(
        referrer_business: referring_business,
        referred_business: new_business,
        referral_code: referral_code,
        status: 'pending'
      )
      
      Rails.logger.info "[PLATFORM_LOYALTY] Created platform referral: Business #{referring_business.id} referred Business #{new_business.id}"
      platform_referral
    end
    
    # Mark referral as qualified and award points (e.g., when first payment is made)
    def qualify_platform_referral(business)
      platform_referral = PlatformReferral.find_by(
        referred_business: business,
        status: 'pending'
      )
      
      return false unless platform_referral
      
      ActiveRecord::Base.transaction do
        platform_referral.mark_qualified!
        award_referral_points(platform_referral)
        platform_referral.mark_rewarded!
      end
      
      Rails.logger.info "[PLATFORM_LOYALTY] Qualified and rewarded platform referral for Business #{business.id}"
      true
    rescue => e
      Rails.logger.error "[PLATFORM_LOYALTY] Error qualifying platform referral: #{e.message}"
      false
    end
    
    # Award points to the referring business
    def award_referral_points(platform_referral)
      platform_referral.referrer_business.add_platform_loyalty_points!(
        REFERRAL_REWARD_POINTS,
        "Business referral reward for referring #{platform_referral.referred_business.name}",
        platform_referral
      )
    end
    
    # Create referral discount for the new business (50% off first month)
    def create_referral_discount(business)
      # Create a Stripe coupon for 50% off first month (only in production or when configured)
      stripe_coupon_id = nil
      if should_create_stripe_coupon?
        stripe_coupon = create_stripe_referral_coupon
        stripe_coupon_id = stripe_coupon.id
      end
      
      # Create platform discount code (not redeemable by points, but as referral reward)
      PlatformDiscountCode.create!(
        business: business,
        code: "BIZBLASTS-REFERRAL-#{SecureRandom.alphanumeric(8).upcase}",
        points_redeemed: 0, # This is a referral reward, not redeemed by points
        discount_amount: 50, # 50% off
        status: 'active',
        stripe_coupon_id: stripe_coupon_id
      )
    end
    
    # Create discount code from loyalty points
    def create_discount_code(business, points_to_redeem)
      return { success: false, error: 'Invalid points amount' } unless valid_redemption_amount?(points_to_redeem)
      return { success: false, error: 'Insufficient points' } unless business.can_redeem_platform_points?(points_to_redeem)
      
      discount_amount = calculate_discount_amount(points_to_redeem)
      
      ActiveRecord::Base.transaction do
        # Create discount code
        discount_code = business.platform_discount_codes.create!(
          points_redeemed: points_to_redeem,
          discount_amount: discount_amount,
          expires_at: 6.months.from_now
        )
        
        # Deduct points
        business.redeem_platform_loyalty_points!(
          points_to_redeem,
          "Redeemed for discount code #{discount_code.code}"
        )
        
        # Create Stripe coupon
        create_stripe_coupon(discount_code)
        
        return { success: true, discount_code: discount_code }
      end
    rescue => e
      Rails.logger.error "[PLATFORM_LOYALTY] Error creating discount code: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Validate discount code for Stripe checkout
    def validate_platform_discount_code(code)
      discount_code = PlatformDiscountCode.find_by(code: code)
      
      unless discount_code
        return { valid: false, error: 'Invalid discount code' }
      end
      
      unless discount_code.can_be_used?
        return { valid: false, error: 'Discount code has already been used' }
      end
      
      # Generate description based on discount type
      description = if discount_code.points_redeemed == 0
        "BizBlasts referral reward - 50% off first month"
      else
        "BizBlasts loyalty reward - $#{discount_code.discount_amount.to_i} off your subscription"
      end
      
      {
        valid: true,
        discount_code: discount_code,
        discount_amount: discount_code.discount_amount,
        description: description
      }
    end
    
    # Mark discount code as used
    def mark_discount_code_used(discount_code)
      discount_code.mark_used!
    end
    
    # Apply discount to Stripe checkout session
    def apply_platform_discount_to_stripe_session(discount_code, session_params)
      return session_params unless discount_code
      
      # Add Stripe coupon to session
      session_params[:discounts] = [{ coupon: discount_code.stripe_coupon_id }] if discount_code.stripe_coupon_id
      
      # Mark as used
      discount_code.mark_used!
      
      session_params
    end
    
    # Mark discount code as used after successful payment
    def mark_discount_code_used(discount_code)
      return unless discount_code
      
      discount_code.mark_used!
      Rails.logger.info "[PLATFORM_LOYALTY] Marked discount code #{discount_code.code} as used"
    end
    
    # Get platform loyalty analytics for a business
    def platform_loyalty_analytics(business)
      {
        current_points: business.current_platform_loyalty_points,
        points_earned: business.platform_points_earned,
        points_redeemed: business.platform_points_redeemed,
        referrals_made: business.platform_referrals_made.count,
        qualified_referrals: business.platform_referrals_made.qualified.count,
        pending_referrals: business.platform_referrals_made.pending.count,
        discount_codes_created: business.platform_discount_codes.count,
        discount_codes_used: business.platform_discount_codes.used.count,
        total_savings: business.platform_discount_codes.used.sum(:discount_amount),
        referral_code: business.platform_referral_code || business.generate_platform_referral_code
      }
    end
    
    # Main method to process business referrals during signup
    def process_business_referral_signup(new_business, referral_code)
      return { success: false, error: 'Referral code is required' } if referral_code.blank?
      return { success: false, error: 'Business is required' } if new_business.blank?
      
      # Find the referring business by their platform referral code
      referring_business = Business.find_by(platform_referral_code: referral_code)
      return { success: false, error: 'Invalid referral code' } unless referring_business
      
      # Check if business is referring themselves
      if referring_business.id == new_business.id
        return { success: false, error: 'Businesses cannot refer themselves' }
      end
      
      # Check if this referral already exists
      existing_referral = PlatformReferral.find_by(
        referrer_business: referring_business,
        referred_business: new_business
      )
      return { success: false, error: 'Referral already exists' } if existing_referral
      
      begin
        ActiveRecord::Base.transaction do
          # Create the platform referral record - immediately qualified for business referrals
          platform_referral = PlatformReferral.create!(
            referrer_business: referring_business,
            referred_business: new_business,
            referral_code: referral_code,
            status: 'qualified'
          )
          
          # Mark as qualified and reward
          platform_referral.update!(status: 'qualified') # Use update! instead of mark_qualified!
          award_referral_points(platform_referral)
          
          # Generate referral discount for the new business (half off first month)
          create_referral_discount(new_business)
          
          # Mark referral as rewarded
          platform_referral.update!(status: 'rewarded') # Use update! instead of mark_rewarded!
          
          return {
            success: true,
            platform_referral: platform_referral,
            points_awarded: REFERRAL_REWARD_POINTS,
            message: "Referral processed successfully! #{referring_business.name} earned #{REFERRAL_REWARD_POINTS} BizBlasts points."
          }
        end
      rescue => e
        Rails.logger.error "Platform referral processing failed: #{e.message}"
        return { success: false, error: 'Failed to process referral' }
      end
    end
    
    def create_stripe_referral_coupon
      Stripe::Coupon.create({
        percent_off: 50,
        duration: 'once',
        name: 'BizBlasts Business Referral - 50% Off First Month',
        metadata: {
          source: 'bizblasts_business_referral'
        }
      })
    end
    
    def redeem_loyalty_points(business, points_amount)
      return { success: false, error: 'Business is required' } if business.blank?
      return { success: false, error: 'Points amount must be positive' } if points_amount <= 0
      return { success: false, error: 'Points must be in multiples of 100' } if points_amount % 100 != 0
      return { success: false, error: 'Maximum 1000 points can be redeemed at once' } if points_amount > 1000
      
      unless business.can_redeem_platform_points?(points_amount)
        return { success: false, error: 'Insufficient loyalty points' }
      end
      
      begin
        ActiveRecord::Base.transaction do
          # Calculate discount amount (100 points = $10)
          discount_amount = calculate_discount_amount(points_amount)
          
          # Create Stripe coupon (will be mocked in tests)
          stripe_coupon_id = nil
          stripe_coupon = create_stripe_loyalty_coupon(discount_amount)
          stripe_coupon_id = stripe_coupon.id
          
          # Create platform discount code
          discount_code = PlatformDiscountCode.create!(
            business: business,
            points_redeemed: points_amount,
            discount_amount: discount_amount,
            status: 'active',
            stripe_coupon_id: stripe_coupon_id
          )
          
          # Deduct points from business
          business.redeem_platform_loyalty_points!(
            points_amount,
            "Redeemed #{points_amount} points for $#{discount_amount.to_i} subscription discount"
          )
          
          return {
            success: true,
            discount_code: discount_code,
            points_redeemed: points_amount,
            discount_amount: discount_amount,
            message: "Successfully redeemed #{points_amount} points for $#{discount_amount.to_i} off your subscription!"
          }
        end
      rescue => e
        Rails.logger.error "Platform loyalty redemption failed: #{e.message}"
        return { success: false, error: 'Failed to redeem loyalty points' }
      end
    end
    
    def create_stripe_loyalty_coupon(discount_amount)
      Stripe::Coupon.create({
        amount_off: (discount_amount * 100).to_i, # Stripe expects cents
        currency: 'usd',
        duration: 'once',
        name: "BizBlasts Loyalty Reward - $#{discount_amount} Off",
        metadata: {
          source: 'bizblasts_loyalty_redemption',
          discount_amount: discount_amount
        }
      })
    end
    
    def generate_business_platform_referral_code(business)
      business.generate_platform_referral_code
    end
    
    def platform_loyalty_summary(business)
      business.platform_loyalty_summary
    end
    
    private
    
    def should_create_stripe_coupon?
      Rails.env.production? || ENV['STRIPE_PUBLISHABLE_KEY'].present? || Rails.env.test?
    end
    
    def valid_redemption_amount?(points)
      (100..MAX_DISCOUNT_POINTS).include?(points) && (points % 100).zero?
    end
    
    def calculate_discount_amount(points)
      (points / 100) * POINTS_TO_DOLLAR_RATE
    end
    
    def create_stripe_coupon(discount_code)
      return unless Rails.env.production? || ENV['STRIPE_PUBLISHABLE_KEY'].present?
      
      begin
        coupon = Stripe::Coupon.create({
          amount_off: (calculate_discount_amount(discount_code.points_redeemed) * 100).to_i, # Stripe expects cents
          currency: 'usd',
          duration: 'once',
          name: "BizBlasts Platform Loyalty Discount",
          metadata: {
            platform_discount_code_id: discount_code.id,
            business_id: discount_code.business_id,
            points_redeemed: discount_code.points_redeemed
          }
        })
        
        discount_code.update!(stripe_coupon_id: coupon.id)
        Rails.logger.info "[PLATFORM_LOYALTY] Created Stripe coupon #{coupon.id} for discount code #{discount_code.code}"
      rescue Stripe::StripeError => e
        Rails.logger.error "[PLATFORM_LOYALTY] Stripe coupon creation failed: #{e.message}"
        # Don't fail the entire transaction, just log the error
      end
    end
  end
end 