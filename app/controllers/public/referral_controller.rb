module Public
  class ReferralController < Public::BaseController
    after_action :no_store!
    before_action :authenticate_user!
    before_action :ensure_client_user
    before_action :set_business, only: [:show]
    before_action :check_referral_program_enabled, only: [:show]

    def index
      # Main domain: this user's own referrals at every business they referred.
      # A business host stays inside that tenant. ActsAsTenant is not disabled
      # for a tenant request.
      referrals = referrals_visible_to_viewer
      @referrals_by_business = referrals.group_by(&:business)
      @referral_stats = referral_stats_for(referrals)
    end

    def show
      # Business-specific referral program (subdomain)
      if current_user&.client?
        @referral_code = ReferralService.generate_referral_code(current_user, @business)
        @referral_url = generate_referral_url(@business, @referral_code) if @referral_code
        @my_referrals = current_user.referrals_made.where(business: @business).includes(:referred_tenant_customer)
        @referral_stats = calculate_user_referral_stats
      else
        # For businesses/staff - show preview but no functionality
        @referral_code = nil
        @referral_url = nil
        @my_referrals = []
        @referral_stats = nil
      end
    end

    private

    def ensure_client_user
      unless current_user&.client?
        if current_user&.manager? || current_user&.staff?
          flash.now[:alert] = 'Referral program is only available for client users'
        else
          redirect_to tenant_root_path, alert: 'Access denied'
        end
      end
    end

    def set_business
      @business = ActsAsTenant.current_tenant
      raise ActiveRecord::RecordNotFound, "Business not found" unless @business
    end

    def check_referral_program_enabled
      unless @business&.referral_program_enabled?
        redirect_to tenant_root_path, alert: 'Referral program is not available for this business'
      end
    end

    def generate_referral_url(business, referral_code)
      TenantHost.url_for(business, request, "/?ref=#{referral_code}")
    end

    def calculate_user_referral_stats
      referrals = current_user.referrals_made.where(business: @business)
      
      {
        total_referrals: referrals.count,
        qualified_referrals: referrals.qualified.count,
        pending_referrals: referrals.pending.count,
        total_rewards_earned: calculate_total_referral_rewards_for_business,
      }
    end

    def calculate_total_referral_rewards_for_business
      # Calculate total loyalty points earned from referrals for this business
      referral_transactions = LoyaltyTransaction.joins(:related_referral)
                                              .where(referrals: { referrer: current_user, business: @business })
                                              .where(transaction_type: 'earned')
      
      referral_transactions.sum(:points_amount)
    end

    # The signed-in user's referral rows only. On a business host that is the
    # current tenant. On the main domain there is no tenant, so the read is
    # explicitly unscoped and still limited to referrer_id = current_user.
    def referrals_visible_to_viewer
      relation = current_user.referrals_made.includes(:business, :referred_tenant_customer)
      if on_business_domain?
        relation.where(business: ActsAsTenant.current_tenant).to_a
      else
        ActsAsTenant.without_tenant { relation.to_a }
      end
    end

    def referral_stats_for(referrals)
      {
        total_referrals: referrals.size,
        qualified_referrals: referrals.count(&:qualified?),
        pending_referrals: referrals.count(&:pending?),
        total_rewards_earned: referral_reward_points(referrals),
        businesses_referred_to: referrals.map(&:business_id).uniq.size
      }
    end

    def referral_reward_points(referrals)
      return 0 if referrals.empty?

      query = lambda {
        LoyaltyTransaction.joins(:related_referral)
                          .where(referrals: { id: referrals.map(&:id), referrer_id: current_user.id })
                          .where(transaction_type: 'earned')
                          .sum(:points_amount)
      }
      on_business_domain? ? query.call : ActsAsTenant.without_tenant(&query)
    end
  end
end 