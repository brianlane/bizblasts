# frozen_string_literal: true

require 'digest'

module EmailMarketing
  module Mailchimp
    # Mailchimp API v3 client
    class Client < BaseClient
      # Get all audiences (lists)
      def get_lists
        response = http_request(:get, "#{api_base}/lists?count=100")

        if response.success?
          response.body['lists'].map do |list|
            {
              id: list['id'],
              name: list['name'],
              member_count: list['stats']['member_count'],
              unsubscribe_count: list['stats']['unsubscribe_count'],
              created_at: list['date_created']
            }
          end
        else
          add_error("Failed to fetch lists: #{response.error_message}")
          []
        end
      end

      # Get a specific list/audience info
      def get_list(list_id)
        response = http_request(:get, "#{api_base}/lists/#{list_id}")

        if response.success?
          response.body
        else
          add_error("Failed to fetch list: #{response.error_message}")
          nil
        end
      end

      # Add a contact to a list
      def add_contact(customer, list_id: nil)
        target_list = list_id || connection.default_list_id
        return add_error('No list ID specified') unless target_list

        subscriber_hash = email_hash(customer.email)
        url = "#{api_base}/lists/#{target_list}/members/#{subscriber_hash}"

        body = build_member_body(customer)
        body['status_if_new'] = 'subscribed'
        body['status'] = customer.unsubscribed_from_emails? ? 'unsubscribed' : 'subscribed'

        response = http_request(:put, url, body: body)

        if response.success?
          # Update customer with Mailchimp info
          customer.update_columns(
            mailchimp_subscriber_hash: subscriber_hash,
            mailchimp_list_id: target_list,
            email_marketing_synced_at: Time.current
          )
          { success: true, subscriber_hash: subscriber_hash, action: response.body['status'] == 'subscribed' ? 'added' : 'updated' }
        else
          add_error("Failed to add contact #{customer.email}: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      # Update an existing contact
      def update_contact(customer, list_id: nil)
        # Mailchimp uses PUT for upsert, so we can reuse add_contact
        add_contact(customer, list_id: list_id)
      end

      # Remove/unsubscribe a contact
      def remove_contact(customer, list_id: nil)
        target_list = list_id || connection.default_list_id || customer.mailchimp_list_id
        return add_error('No list ID specified') unless target_list

        subscriber_hash = customer.mailchimp_subscriber_hash || email_hash(customer.email)
        url = "#{api_base}/lists/#{target_list}/members/#{subscriber_hash}"

        # Use PATCH to update status to unsubscribed rather than DELETE
        response = http_request(:patch, url, body: { status: 'unsubscribed' })

        if response.success?
          { success: true, action: 'unsubscribed' }
        elsif response.status == 404
          # Contact not found, that's fine
          { success: true, action: 'not_found' }
        else
          add_error("Failed to remove contact #{customer.email}: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      # Get contact info
      def get_contact(email, list_id: nil)
        target_list = list_id || connection.default_list_id
        return nil unless target_list

        subscriber_hash = email_hash(email)
        response = http_request(:get, "#{api_base}/lists/#{target_list}/members/#{subscriber_hash}")

        if response.success?
          response.body
        elsif response.status == 404
          nil
        else
          add_error("Failed to get contact: #{response.error_message}")
          nil
        end
      end

      # Batch add/update contacts
      def batch_add_contacts(customers, list_id: nil)
        target_list = list_id || connection.default_list_id
        return add_error('No list ID specified') unless target_list

        operations = customers.map do |customer|
          subscriber_hash = email_hash(customer.email)
          {
            method: 'PUT',
            path: "/lists/#{target_list}/members/#{subscriber_hash}",
            body: build_member_body(customer).merge(
              'status_if_new' => 'subscribed',
              'status' => customer.unsubscribed_from_emails? ? 'unsubscribed' : 'subscribed'
            ).to_json
          }
        end

        response = http_request(:post, "#{api_base}/batches", body: { operations: operations })

        if response.success?
          batch_id = response.body['id']
          Rails.logger.info "[Mailchimp::Client] Batch operation started: #{batch_id} with #{operations.size} operations"
          { success: true, batch_id: batch_id, operation_count: operations.size }
        else
          add_error("Batch operation failed: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      # Check batch operation status
      def get_batch_status(batch_id)
        response = http_request(:get, "#{api_base}/batches/#{batch_id}")

        if response.success?
          {
            id: response.body['id'],
            status: response.body['status'],
            total_operations: response.body['total_operations'],
            finished_operations: response.body['finished_operations'],
            errored_operations: response.body['errored_operations'],
            completed_at: response.body['completed_at']
          }
        else
          nil
        end
      end

      # Register a webhook for list updates
      def register_webhook(list_id, webhook_url)
        response = http_request(
          :post,
          "#{api_base}/lists/#{list_id}/webhooks",
          body: {
            url: webhook_url,
            events: {
              subscribe: true,
              unsubscribe: true,
              profile: true,
              cleaned: true,
              upemail: true
            },
            sources: {
              user: true,
              admin: true,
              api: false  # Don't trigger on our own API calls
            }
          }
        )

        if response.success?
          { success: true, webhook_id: response.body['id'] }
        else
          add_error("Failed to register webhook: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      private

      def api_base
        datacenter = connection.api_server || 'us1'
        MailchimpOauthCredentials.api_base_url(datacenter)
      end

      def default_headers
        {
          'Authorization' => "Bearer #{connection.access_token}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      def email_hash(email)
        Digest::MD5.hexdigest(email.downcase.strip)
      end

      def build_member_body(customer)
        merge_fields = {
          'FNAME' => customer.first_name.to_s,
          'LNAME' => customer.last_name.to_s
        }

        # Add phone if available
        merge_fields['PHONE'] = customer.phone if customer.phone.present?

        # Add custom merge fields based on connection config
        if connection.field_mappings.present?
          connection.field_mappings.each do |local_field, mc_field|
            value = customer.try(local_field)
            merge_fields[mc_field] = value.to_s if value.present?
          end
        end

        {
          'email_address' => customer.email,
          'merge_fields' => merge_fields
        }
      end
    end
  end
end
