# frozen_string_literal: true

module EmailMarketing
  module ConstantContact
    # Service for syncing contacts to Constant Contact
    class ContactSyncService < BaseSyncService
      protected

      # Scope for customers that have never been synced to Constant Contact
      def never_synced_to_provider_scope(base_scope)
        base_scope.where(constant_contact_id: nil)
      end

      def sync_in_batches(customers, list_id)
        # Constant Contact uses activity-based bulk import
        result = api_client.batch_add_contacts(customers, list_id: list_id)

        if result[:success]
          # Mark all as synced optimistically
          customers.each do |customer|
            customer.update_columns(email_marketing_synced_at: Time.current)
          end

          # Store activity ID in sync log for later verification
          @sync_log.update!(
            summary: (@sync_log.summary || {}).merge(
              activity_id: result[:activity_id],
              activity_queued: true
            ),
            contacts_synced: customers.size
          )

          Rails.logger.info "[ConstantContact::ContactSyncService] Activity #{result[:activity_id]} queued with #{customers.size} contacts"
        else
          # Batch failed, try individual sync
          Rails.logger.warn "[ConstantContact::ContactSyncService] Batch failed, falling back to individual sync"
          sync_individually(customers, list_id)
        end
      end

      # Check status of an import activity
      def check_activity_status(activity_id)
        status = api_client.get_activity_status(activity_id)
        return unless status

        if status[:status] == 'COMPLETED' || status[:status] == 'completed'
          @sync_log.update!(
            summary: (@sync_log.summary || {}).merge(
              activity_completed: true,
              activity_status: status
            )
          )
        end

        status
      end

      # Handle incoming webhook data
      def handle_webhook(webhook_data)
        return unless webhook_data

        event_type = webhook_data['event_type'] || webhook_data['topic_id']

        case event_type
        when 'contacts.unsubscribe', 'contact.unsubscribe'
          handle_unsubscribe(webhook_data)
        when 'contacts.subscribe', 'contact.subscribe'
          handle_subscribe(webhook_data)
        when 'contacts.update', 'contact.update'
          handle_profile_update(webhook_data)
        when 'contacts.delete', 'contact.delete'
          handle_delete(webhook_data)
        end
      end

      private

      def handle_unsubscribe(data)
        contact_id = data['contact_id'] || data.dig('data', 'contact_id')
        email = data['email_address'] || data.dig('data', 'email_address')

        customer = find_customer(contact_id: contact_id, email: email)
        return unless customer

        log = EmailMarketingSyncLog.create!(
          email_marketing_connection: connection,
          business: connection.business,
          sync_type: :single_contact,
          status: :running,
          direction: :inbound,
          started_at: Time.current
        )

        customer.update!(email_marketing_opt_out: true)

        log.complete!(
          action: 'unsubscribe',
          customer_id: customer.id,
          source: 'webhook'
        )

        Rails.logger.info "[ConstantContact::ContactSyncService] Customer #{customer.id} unsubscribed via webhook"
      end

      def handle_subscribe(data)
        contact_id = data['contact_id'] || data.dig('data', 'contact_id')
        email = data['email_address'] || data.dig('data', 'email_address')

        customer = find_customer(contact_id: contact_id, email: email)
        return unless customer

        customer.update!(email_marketing_opt_out: false)
        Rails.logger.info "[ConstantContact::ContactSyncService] Customer #{customer.id} subscribed via webhook"
      end

      def handle_profile_update(data)
        contact_id = data['contact_id'] || data.dig('data', 'contact_id')
        email = data['email_address'] || data.dig('data', 'email_address')
        contact_data = data['contact'] || data.dig('data', 'contact') || data

        customer = find_customer(contact_id: contact_id, email: email)
        return unless customer

        updates = {}
        updates[:first_name] = contact_data['first_name'] if contact_data['first_name'].present?
        updates[:last_name] = contact_data['last_name'] if contact_data['last_name'].present?

        if contact_data['phone_numbers'].present?
          phone = contact_data['phone_numbers'].first
          updates[:phone] = phone['phone_number'] if phone && phone['phone_number'].present?
        end

        customer.update!(updates) if updates.present?
        Rails.logger.info "[ConstantContact::ContactSyncService] Customer #{customer.id} profile updated via webhook"
      end

      def handle_delete(data)
        contact_id = data['contact_id'] || data.dig('data', 'contact_id')
        email = data['email_address'] || data.dig('data', 'email_address')

        customer = find_customer(contact_id: contact_id, email: email)
        return unless customer

        customer.update!(
          constant_contact_id: nil,
          email_marketing_opt_out: true
        )

        Rails.logger.info "[ConstantContact::ContactSyncService] Customer #{customer.id} deleted from Constant Contact via webhook"
      end

      def find_customer(contact_id: nil, email: nil)
        if contact_id.present?
          customer = connection.business.tenant_customers.find_by(constant_contact_id: contact_id)
          return customer if customer
        end

        if email.present?
          connection.business.tenant_customers.find_by(email: email.downcase)
        end
      end
    end
  end
end
