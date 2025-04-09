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

  private

  # Helper method available to all policies inheriting from ApplicationPolicy.
  def admin?
    # Check if the user is an instance of AdminUser
    # Adjust this check if other admin types exist.
    user.is_a?(AdminUser)
  end
end
