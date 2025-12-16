# frozen_string_literal: true

module EmailMarketing
  # Job for syncing a single customer to email marketing platforms
  class SyncSingleContactJob < ApplicationJob
    queue_as :email_marketing

    # Retry on common transient errors
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # Discard if the customer no longer exists
    discard_on ActiveRecord::RecordNotFound

    # @param customer_id [Integer] The TenantCustomer ID
    # @param provider [String, nil] Optional specific provider ('mailchimp' or 'constant_contact')
    #   If nil, syncs to all connected platforms
    # @param action [String] 'sync' (add/update) or 'remove'
    def perform(customer_id, provider = nil, action = 'sync')
      customer = TenantCustomer.find(customer_id)
      business = customer.business

      ActsAsTenant.with_tenant(business) do
        connections = if provider.present?
                        business.email_marketing_connections.active.where(provider: provider)
                      else
                        business.email_marketing_connections.active
                      end

        connections.find_each do |connection|
          next unless connection.connected?
          next unless should_sync?(connection, action)

          sync_service = connection.sync_service

          result = case action
                   when 'remove'
                     sync_service.remove_customer(customer)
                   else
                     sync_service.sync_customer(customer)
                   end

          if result[:success]
            Rails.logger.info "[EmailMarketing::SyncSingleContactJob] #{action.capitalize}d customer #{customer_id} to #{connection.provider_name}"
          else
            Rails.logger.error "[EmailMarketing::SyncSingleContactJob] Failed to #{action} customer #{customer_id} to #{connection.provider_name}: #{result[:error]}"
          end
        end
      end
    end

    private

    def should_sync?(connection, action)
      case action
      when 'sync'
        connection.sync_on_customer_create || connection.sync_on_customer_update
      when 'remove'
        true # Always allow remove
      else
        false
      end
    end
  end
end
