# frozen_string_literal: true

# Base policy for the application. All other policies inherit from this.
# Provides default authorization rules.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    # user is the currently logged-in user (e.g., AdminUser)
    # record is the model instance being authorized (or the class for index/create)
    @user = user
    @record = record
  end

  # Default policy: Allow action if the user is an admin.
  # Subclasses should override these for more specific logic.
  def index?
    admin?
  end

  def show?
    admin?
  end

  def create?
    admin?
  end

  def new?
    create?
  end

  def update?
    admin?
  end

  def edit?
    update?
  end

  def destroy?
    admin?
  end

  # Base scope class. Subclasses should define `resolve`.
  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    # Default scope: Return all records if the user is an admin.
    # Subclasses should override for more specific scoping (e.g., tenant scoping).
    def resolve
      admin? ? scope.all : scope.none
    end

    private

    # Helper method to check if the user is an admin.
    # Assumes the user object is an AdminUser.
    def admin?
      # Check if the user is an instance of AdminUser
      # Adjust this check if other admin types exist.
      user.is_a?(AdminUser)
    end
  end

  protected

  # Helper method available to all policies inheriting from ApplicationPolicy.
  def admin?
    # Check if the user is an instance of AdminUser
    # Adjust this check if other admin types exist.
    user.is_a?(AdminUser)
  end

  # Helper methods for tenant-aware policies
  def user_owns_business?
    user.respond_to?(:business_id) && user.business_id.present?
  end

  def record_belongs_to_user_business?
    return false unless user_owns_business?
    return false unless record.respond_to?(:business_id)
    
    record.business_id == user.business_id
  end

  def user_is_business_manager?
    user.respond_to?(:manager?) && user.manager? && user_owns_business?
  end

  def user_is_business_staff?
    user.respond_to?(:staff?) && user.staff? && user_owns_business?
  end

  def user_is_client?
    user.respond_to?(:client?) && user.client?
  end

  # Log security violations for monitoring
  def log_authorization_failure(action)
    SecureLogger.security_event('authorization_failure', {
      user_id: user&.id,
      user_type: user.class.name,
      action: action,
      resource: record.class.name,
      resource_id: record.respond_to?(:id) ? record.id : nil
    })
  end
end
