# frozen_string_literal: true

module BusinessManager
  module Settings
    class TeamsController < BusinessManager::BaseController
      before_action :set_staff_member, only: [:destroy]

      # GET /manage/settings/teams
      def index
        @staff_members = policy_scope(current_business.staff_members).includes(:user).order('LOWER(name)')
      end

      # GET /manage/settings/teams/new
      def new
        @staff_member = current_business.staff_members.new
        @staff_member.build_user
        authorize @staff_member, :new?, policy_class: ::Settings::TeamPolicy
      end

      # POST /manage/settings/teams
      def create
        authorize StaffMember, :create?, policy_class: ::Settings::TeamPolicy
        user_attrs = team_member_params[:user_attributes] || {}
        @user = User.new(user_attrs.merge(role: 'staff', business_id: current_business.id))
        if @user.save
          @user.send_reset_password_instructions
          @staff_member = current_business.staff_members.new(team_member_params.except(:user_attributes))
          @staff_member.user = @user

          if @staff_member.save
            redirect_to business_manager_settings_teams_path, notice: 'Team member invited successfully.'
          else
            @staff_member.build_user(user_attrs)
            flash.now[:alert] = @staff_member.errors.full_messages.to_sentence
            render :new, status: :unprocessable_entity
          end
        else
          @staff_member = current_business.staff_members.new(team_member_params.except(:user_attributes))
          @staff_member.build_user(user_attrs)
          @staff_member.errors.add(:user, @user.errors.full_messages.to_sentence)
          flash.now[:alert] = @staff_member.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      # DELETE /manage/settings/teams/:id
      def destroy
        authorize @staff_member, policy_class: ::Settings::TeamPolicy
        @staff_member.destroy
        redirect_to business_manager_settings_teams_path, notice: 'Team member removed.'
      end

      private

      def set_staff_member
        @staff_member = current_business.staff_members.find(params[:id])
      end

      def team_member_params
        params.require(:staff_member).permit(
          :name,
          :phone,
          :position,
          user_attributes: [:first_name, :last_name, :email, :password, :password_confirmation]
        )
      end
    end
  end
end 