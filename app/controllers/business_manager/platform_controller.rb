class BusinessManager::PlatformController < BusinessManager::BaseController
  before_action :authenticate_user!
  before_action :ensure_business_manager!
  
  def index
    @loyalty_summary = PlatformLoyaltyService.platform_loyalty_summary(current_business)
    @recent_transactions = current_business.platform_loyalty_transactions.recent.limit(10)
    @recent_referrals = current_business.platform_referrals_made.recent.limit(10)
    @discount_codes = current_business.platform_discount_codes.recent.limit(5)
    @redemption_options = PlatformDiscountCode.available_redemptions_for_business(current_business)
  end
  
  def generate_referral_code
    begin
      referral_code = PlatformLoyaltyService.generate_business_platform_referral_code(current_business)
      
      respond_to do |format|
        format.json do
          render json: {
            success: true,
            referral_code: referral_code,
            message: 'Referral code generated successfully!'
          }
        end
        format.html do
          flash[:success] = 'Referral code generated successfully!'
          redirect_to business_manager_platform_index_path
        end
      end
    rescue => e
      Rails.logger.error "Failed to generate platform referral code: #{e.message}"
      
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: 'Failed to generate referral code'
          }, status: 422
        end
        format.html do
          flash[:error] = 'Failed to generate referral code'
          redirect_to business_manager_platform_index_path
        end
      end
    end
  end
  
  def redeem_points
    points_amount = params[:points_amount].to_i
    
    result = PlatformLoyaltyService.redeem_loyalty_points(current_business, points_amount)
    
    respond_to do |format|
      format.json do
        if result[:success]
          render json: {
            success: true,
            discount_code: result[:discount_code].code,
            points_redeemed: result[:points_redeemed],
            discount_amount: result[:discount_amount],
            message: result[:message]
          }
        else
          render json: {
            success: false,
            error: result[:error]
          }, status: 422
        end
      end
      format.html do
        if result[:success]
          flash[:success] = result[:message]
        else
          flash[:error] = result[:error]
        end
        redirect_to business_manager_platform_index_path
      end
    end
  end
  
  def transactions
    @transactions = current_business.platform_loyalty_transactions
                                  .includes(:related_platform_referral)
                                  .recent
                                  .page(params[:page])
                                  .per(25)
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          transactions: @transactions.map do |transaction|
            {
              id: transaction.id,
              transaction_type: transaction.transaction_type,
              points_amount: transaction.points_amount,
              description: transaction.description,
              created_at: transaction.created_at.strftime('%m/%d/%Y %I:%M %p'),
              related_referral: transaction.related_platform_referral&.referred_business&.name
            }
          end,
          meta: {
            current_page: @transactions.current_page,
            total_pages: @transactions.total_pages,
            total_count: @transactions.total_count
          }
        }
      end
    end
  end
  
  def referrals
    @referrals = current_business.platform_referrals_made
                               .includes(:referred_business)
                               .recent
                               .page(params[:page])
                               .per(25)
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          referrals: @referrals.map do |referral|
            {
              id: referral.id,
              referral_code: referral.referral_code,
              referred_business: {
                name: referral.referred_business.name,
                tier: referral.referred_business.tier
              },
              status: referral.status,
              qualification_met_at: referral.qualification_met_at&.strftime('%m/%d/%Y %I:%M %p'),
              reward_issued_at: referral.reward_issued_at&.strftime('%m/%d/%Y %I:%M %p'),
              created_at: referral.created_at.strftime('%m/%d/%Y %I:%M %p')
            }
          end,
          meta: {
            current_page: @referrals.current_page,
            total_pages: @referrals.total_pages,
            total_count: @referrals.total_count
          }
        }
      end
    end
  end
  
  def discount_codes
    @discount_codes = current_business.platform_discount_codes
                                    .recent
                                    .page(params[:page])
                                    .per(25)
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          discount_codes: @discount_codes.map do |code|
            {
              id: code.id,
              code: code.code,
              points_redeemed: code.points_redeemed,
              discount_amount: code.discount_amount,
              display_discount: code.display_discount,
              status: code.status,
              expires_at: code.expires_at&.strftime('%m/%d/%Y %I:%M %p'),
              created_at: code.created_at.strftime('%m/%d/%Y %I:%M %p')
            }
          end,
          meta: {
            current_page: @discount_codes.current_page,
            total_pages: @discount_codes.total_pages,
            total_count: @discount_codes.total_count
          }
        }
      end
    end
  end
  
  private
  
  def ensure_business_manager!
    unless current_user.business_manager?(current_business)
      respond_to do |format|
        format.html do
          flash[:error] = 'You are not authorized to access this page.'
          redirect_to root_path
        end
        format.json do
          render json: { error: 'Unauthorized' }, status: :forbidden
        end
      end
    end
  end
end 