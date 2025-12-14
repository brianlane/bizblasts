# frozen_string_literal: true

module Quickbooks
  class TokenRefreshJob < ApplicationJob
    queue_as :default

    def perform(business_id)
      business = Business.find(business_id)
      connection = business.quickbooks_connection
      return unless connection&.active?

      return unless connection.needs_refresh?

      handler = Quickbooks::OauthHandler.new
      ActsAsTenant.with_tenant(business) do
        handler.refresh_token(connection)
      end
    end
  end
end
