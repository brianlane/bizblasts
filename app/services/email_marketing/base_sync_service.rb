# frozen_string_literal: true

module EmailMarketing
  # Base sync service with shared functionality
  class BaseSyncService
    attr_reader :connection, :errors, :sync_log

    def initialize(connection)
      @connection = connection
      @errors = []
    end

    # Sync all customers to the email marketing platform
    def sync_all(list_id: nil)
      return error_result('Connection is not active') unless connection.connected?

      target_list = list_id || connection.default_list_id
      return error_result('No list ID specified') unless target_list

      @sync_log = create_sync_log(:full_sync)
      @sync_log.start!

      begin
        customers = fetch_customers_to_sync
        Rails.logger.info "[#{self.class.name}] Syncing #{customers.size} customers to #{connection.provider_name}"

        if customers.size > batch_threshold
          sync_in_batches(customers, target_list)
        else
          sync_individually(customers, target_list)
        end

        @sync_log.complete!(
          total_customers: customers.size,
          provider: connection.provider,
          list_id: target_list
        )

        connection.record_sync!(contacts_synced: @sync_log.contacts_synced)

        success_result
      rescue StandardError => e
        @sync_log.fail!(e.message)
        Rails.logger.error "[#{self.class.name}] Sync failed: #{e.message}"
        error_result(e.message)
      end
    end

    # Sync customers updated since last sync
    def sync_incremental(list_id: nil)
      return error_result('Connection is not active') unless connection.connected?

      target_list = list_id || connection.default_list_id
      return error_result('No list ID specified') unless target_list

      @sync_log = create_sync_log(:incremental)
      @sync_log.start!

      begin
        since = connection.last_synced_at || 24.hours.ago
        customers = fetch_customers_updated_since(since)

        Rails.logger.info "[#{self.class.name}] Incremental sync: #{customers.size} customers updated since #{since}"

        sync_individually(customers, target_list)

        @sync_log.complete!(
          total_customers: customers.size,
          provider: connection.provider,
          list_id: target_list,
          since: since.iso8601
        )

        connection.record_sync!(contacts_synced: @sync_log.contacts_synced)

        success_result
      rescue StandardError => e
        @sync_log.fail!(e.message)
        error_result(e.message)
      end
    end

    # Sync a single customer
    def sync_customer(customer, list_id: nil)
      return error_result('Connection is not active') unless connection.connected?

      target_list = list_id || connection.default_list_id
      return error_result('No list ID specified') unless target_list

      @sync_log = create_sync_log(:single_contact)
      @sync_log.start!

      begin
        result = sync_single_customer(customer, target_list)

        if result[:success]
          @sync_log.increment_synced!
          @sync_log.complete!(customer_id: customer.id, action: result[:action])
        else
          @sync_log.increment_failed!
          @sync_log.add_error(result[:error])
          @sync_log.complete!(customer_id: customer.id, error: result[:error])
        end

        result
      rescue StandardError => e
        @sync_log.fail!(e.message)
        error_result(e.message)
      end
    end

    # Remove a customer from the email platform
    def remove_customer(customer, list_id: nil)
      return error_result('Connection is not active') unless connection.connected?

      api_client.remove_contact(customer, list_id: list_id)
    end

    protected

    def api_client
      @api_client ||= connection.api_client
    end

    # Returns the threshold above which batch API should be used
    # Configurable per provider via config/initializers/email_marketing.rb
    # or via environment variables (EMAIL_MARKETING_*_BATCH_THRESHOLD)
    def batch_threshold
      thresholds = Rails.application.config.email_marketing.batch_thresholds
      thresholds[connection.provider.to_sym] || thresholds[:default] || 50
    end

    def sync_individually(customers, list_id)
      customers.each do |customer|
        result = sync_single_customer(customer, list_id)
        if result[:success]
          if result[:action] == 'created'
            @sync_log.increment_created!
          else
            @sync_log.increment_updated!
          end
        else
          @sync_log.increment_failed!
          @sync_log.add_error("#{customer.email}: #{result[:error]}")
        end
      end
    end

    def sync_in_batches(customers, list_id)
      raise NotImplementedError, 'Subclass must implement #sync_in_batches'
    end

    def sync_single_customer(customer, list_id)
      api_client.add_contact(customer, list_id: list_id)
    end

    def fetch_customers_to_sync
      connection.business.tenant_customers
                .active
                .where.not(email: nil)
                .where.not(email: '')
    end

    def fetch_customers_updated_since(since)
      base_scope = connection.business.tenant_customers
                             .active
                             .where.not(email: nil)
                             .where.not(email: '')

      # Check for customers that either:
      # 1. Were updated since the last sync, OR
      # 2. Have never been synced to THIS specific provider (provider-specific ID is null)
      #
      # This ensures a newly-connected second provider's first incremental sync
      # includes all customers, not just recently updated ones.
      updated_since = base_scope.where(base_scope.arel_table[:updated_at].gt(since))
      never_synced = never_synced_to_provider_scope(base_scope)

      # Combine with OR using Arel to avoid SQL injection
      updated_since.or(never_synced)
    end

    # Override in subclass to provide scope for customers never synced to this provider
    # Default: customers with null email_marketing_synced_at
    def never_synced_to_provider_scope(base_scope)
      base_scope.where(email_marketing_synced_at: nil)
    end

    private

    def create_sync_log(sync_type)
      EmailMarketingSyncLog.create!(
        email_marketing_connection: connection,
        business: connection.business,
        sync_type: sync_type,
        status: :pending,
        direction: :outbound
      )
    end

    def success_result
      {
        success: true,
        synced: @sync_log.contacts_synced,
        created: @sync_log.contacts_created,
        updated: @sync_log.contacts_updated,
        failed: @sync_log.contacts_failed,
        sync_log_id: @sync_log.id
      }
    end

    def error_result(message)
      @errors << message
      { success: false, error: message }
    end
  end
end
