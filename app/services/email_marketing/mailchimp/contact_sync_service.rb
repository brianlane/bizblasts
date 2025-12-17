# frozen_string_literal: true

module EmailMarketing
  module Mailchimp
    # Service for syncing contacts to Mailchimp
    class ContactSyncService < BaseSyncService
      protected

      # Scope for customers that have never been synced to Mailchimp
      def never_synced_to_provider_scope(base_scope)
        base_scope.where(mailchimp_subscriber_hash: nil)
      end

      def sync_in_batches(customers, list_id)
        # Mailchimp has a batch API for bulk operations
        result = api_client.batch_add_contacts(customers, list_id: list_id)

        if result[:success]
          # Batch was queued - we won't know individual results immediately
          # Mark all as synced optimistically
          customers.each do |customer|
            customer.update_columns(
              mailchimp_list_id: list_id,
              email_marketing_synced_at: Time.current
            )
          end

          # Store batch ID in sync log for later verification
          @sync_log.update!(
            summary: (@sync_log.summary || {}).merge(
              batch_id: result[:batch_id],
              batch_queued: true
            ),
            contacts_synced: customers.size
          )

          Rails.logger.info "[Mailchimp::ContactSyncService] Batch #{result[:batch_id]} queued with #{customers.size} contacts"
        else
          # Batch failed, try individual sync
          Rails.logger.warn "[Mailchimp::ContactSyncService] Batch failed, falling back to individual sync"
          sync_individually(customers, list_id)
        end
      end

      # Check status of a batch operation and update sync log
      def check_batch_status(batch_id)
        status = api_client.get_batch_status(batch_id)
        return unless status

        if status[:status] == 'finished'
          @sync_log.update!(
            summary: (@sync_log.summary || {}).merge(
              batch_completed: true,
              batch_status: status
            ),
            contacts_synced: status[:finished_operations].to_i,
            contacts_failed: status[:errored_operations].to_i
          )
        end

        status
      end

      # Handle incoming webhook data (unsubscribes, profile updates, etc.)
      def handle_webhook(webhook_data)
        return unless webhook_data

        case webhook_data['type']
        when 'unsubscribe'
          handle_unsubscribe(webhook_data['data'])
        when 'subscribe'
          handle_subscribe(webhook_data['data'])
        when 'profile'
          handle_profile_update(webhook_data['data'])
        when 'cleaned'
          handle_cleaned(webhook_data['data'])
        when 'upemail'
          handle_email_change(webhook_data['data'])
        end
      end

      private

      def handle_unsubscribe(data)
        email = data['email']
        list_id = data['list_id']

        customer = find_customer_by_email(email)
        return unless customer

        # Record this as an inbound sync
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

        Rails.logger.info "[Mailchimp::ContactSyncService] Customer #{customer.id} unsubscribed via webhook"
      end

      def handle_subscribe(data)
        email = data['email']

        customer = find_customer_by_email(email)
        return unless customer

        customer.update!(email_marketing_opt_out: false)
        Rails.logger.info "[Mailchimp::ContactSyncService] Customer #{customer.id} subscribed via webhook"
      end

      def handle_profile_update(data)
        email = data['email']
        merges = data['merges'] || {}

        customer = find_customer_by_email(email)
        return unless customer

        # Update customer profile with new data from Mailchimp
        updates = {}
        updates[:first_name] = merges['FNAME'] if merges['FNAME'].present?
        updates[:last_name] = merges['LNAME'] if merges['LNAME'].present?
        updates[:phone] = merges['PHONE'] if merges['PHONE'].present?

        customer.update!(updates) if updates.present?
        Rails.logger.info "[Mailchimp::ContactSyncService] Customer #{customer.id} profile updated via webhook"
      end

      def handle_cleaned(data)
        email = data['email']

        customer = find_customer_by_email(email)
        return unless customer

        # Email was cleaned (bounced/invalid) - mark as inactive
        customer.update!(
          email_marketing_opt_out: true,
          notes: [customer.notes, "Email marked as cleaned/invalid by Mailchimp on #{Time.current}"].compact.join("\n")
        )

        Rails.logger.info "[Mailchimp::ContactSyncService] Customer #{customer.id} email cleaned via webhook"
      end

      def handle_email_change(data)
        old_email = data['old_email']
        new_email = data['new_email']

        customer = find_customer_by_email(old_email)
        return unless customer

        # Update customer email
        customer.update!(email: new_email, mailchimp_subscriber_hash: nil)
        Rails.logger.info "[Mailchimp::ContactSyncService] Customer #{customer.id} email changed via webhook"
      end

      def find_customer_by_email(email)
        connection.business.tenant_customers.find_by(email: email.downcase)
      end
    end
  end
end
