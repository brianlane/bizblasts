# frozen_string_literal: true

class Client::SettingsPolicy < ApplicationPolicy
  def show?
    user_is_record_owner_and_client?
  end

  def edit?
    user_is_record_owner_and_client?
  end

  def update?
    user_is_record_owner_and_client?
  end

  def destroy?
    user_is_record_owner_and_client?
  end

  private

  def user_is_record_owner_and_client?
    user.present? && user == record && user.client?
  end

  # Scope class for pundit
  class Scope < Scope
    def resolve
      # Clients should only see their own settings, so a typical scope for index isn't applicable here.
      # If there were an index action for admins viewing client settings, it would be different.
      scope.none # Or raise Pundit::NotDefinedError, "Cannot scope client settings."
    end
  end
end 