module Public
  class ReferralController < Public::BaseController
    after_action :no_store!
    before_action :authenticate_user!
    before_action :ensure_client_user
    before_action :set_business, only: [:show]
    before_action :check_referral_program_enabled, only: [:show]

    def index
      # Cross-business referral overview (main domain)
      @referrals_by_business = current_user.referrals_made
                                          .includes(:business, :referred_tenant_customer)
                                          .group_by(&:business)
      @referral_stats = calculate_user_referral_stats_all_businesses
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

    def calculate_user_referral_stats_all_businesses
      # Cross-business referral stats for main domain
      referrals = current_user.referrals_made
      
      {
        total_referrals: referrals.count,
        qualified_referrals: referrals.qualified.count,
        pending_referrals: referrals.pending.count,
        total_rewards_earned: calculate_total_referral_rewards_all_businesses,
        businesses_referred_to: referrals.joins(:business).distinct.count('businesses.id')
      }
    end

    def calculate_total_referral_rewards_all_businesses
      # Calculate total loyalty points earned from referrals across all businesses
      referral_transactions = LoyaltyTransaction.joins(:related_referral)
                                              .where(referrals: { referrer: current_user })
                                              .where(transaction_type: 'earned')
      
      referral_transactions.sum(:points_amount)
    end
  end
end 