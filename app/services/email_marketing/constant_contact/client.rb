# frozen_string_literal: true

module EmailMarketing
  module ConstantContact
    # Constant Contact API v3 client
    class Client < BaseClient
      # Get all contact lists
      def get_lists
        response = http_request(:get, "#{api_base}/contact_lists?include_count=true&include_membership_count=all")

        if response.success?
          response.body['lists'].map do |list|
            {
              id: list['list_id'],
              name: list['name'],
              member_count: list['membership_count'],
              created_at: list['created_at'],
              updated_at: list['updated_at']
            }
          end
        else
          add_error("Failed to fetch lists: #{response.error_message}")
          []
        end
      end

      # Get a specific list
      def get_list(list_id)
        response = http_request(:get, "#{api_base}/contact_lists/#{list_id}")

        if response.success?
          response.body
        else
          add_error("Failed to fetch list: #{response.error_message}")
          nil
        end
      end

      # Add a contact
      def add_contact(customer, list_id: nil)
        target_list = list_id || connection.default_list_id

        # First check if contact exists
        existing = get_contact_by_email(customer.email)

        if existing
          # Update existing contact
          result = update_existing_contact(existing['contact_id'], customer, target_list)
          customer.update_columns(
            constant_contact_id: existing['contact_id'],
            email_marketing_synced_at: Time.current
          ) if result[:success]
          return result
        end

        # Create new contact
        body = build_contact_body(customer, target_list)

        response = http_request(:post, "#{api_base}/contacts", body: body)

        if response.success?
          contact_id = response.body['contact_id']
          customer.update_columns(
            constant_contact_id: contact_id,
            email_marketing_synced_at: Time.current
          )
          { success: true, contact_id: contact_id, action: 'created' }
        else
          add_error("Failed to add contact #{customer.email}: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      # Update a contact
      def update_contact(customer, list_id: nil)
        contact_id = customer.constant_contact_id

        unless contact_id
          # Try to find by email
          existing = get_contact_by_email(customer.email)
          contact_id = existing['contact_id'] if existing
        end

        unless contact_id
          # Contact doesn't exist, create it
          return add_contact(customer, list_id: list_id)
        end

        update_existing_contact(contact_id, customer, list_id || connection.default_list_id)
      end

      # Remove a contact from a list (or delete entirely)
      def remove_contact(customer, list_id: nil)
        contact_id = customer.constant_contact_id

        unless contact_id
          existing = get_contact_by_email(customer.email)
          contact_id = existing['contact_id'] if existing
        end

        return { success: true, action: 'not_found' } unless contact_id

        target_list = list_id || connection.default_list_id

        if target_list
          # Remove from specific list
          response = http_request(
            :delete,
            "#{api_base}/contacts/#{contact_id}/list_memberships/#{target_list}"
          )
        else
          # Delete contact entirely
          response = http_request(:delete, "#{api_base}/contacts/#{contact_id}")
        end

        if response.success? || response.status == 204
          { success: true, action: 'removed' }
        elsif response.status == 404
          { success: true, action: 'not_found' }
        else
          add_error("Failed to remove contact: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      # Get contact by email
      def get_contact(email, list_id: nil)
        get_contact_by_email(email)
      end

      # Batch add/update contacts using Constant Contact's bulk import
      def batch_add_contacts(customers, list_id: nil)
        target_list = list_id || connection.default_list_id
        return add_error('No list ID specified') unless target_list

        import_data = customers.map do |customer|
          {
            email: customer.email,
            first_name: customer.first_name.to_s,
            last_name: customer.last_name.to_s,
            phone: customer.phone.to_s
          }.compact_blank
        end

        body = {
          import_data: import_data,
          list_ids: [target_list]
        }

        response = http_request(:post, "#{api_base}/activities/contacts_json_import", body: body)

        if response.success?
          activity_id = response.body['activity_id']
          Rails.logger.info "[ConstantContact::Client] Import activity started: #{activity_id} with #{import_data.size} contacts"
          { success: true, activity_id: activity_id, contact_count: import_data.size }
        else
          add_error("Batch import failed: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      # Check activity/import status
      def get_activity_status(activity_id)
        response = http_request(:get, "#{api_base}/activities/#{activity_id}")

        if response.success?
          {
            id: response.body['activity_id'],
            status: response.body['state'],
            percent_done: response.body['percent_done'],
            start_date: response.body['start_date'],
            completed_date: response.body['completed_date']
          }
        else
          nil
        end
      end

      # Register webhook
      def register_webhook(webhook_url, topic = 'contacts.subscribe')
        body = {
          hook_uri: webhook_url,
          topic_id: topic
        }

        response = http_request(:post, "#{api_base}/partner/webhooks", body: body)

        if response.success?
          { success: true, hook_id: response.body['hook_id'] }
        else
          add_error("Failed to register webhook: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      private

      def api_base
        ConstantContactOauthCredentials.api_base_url
      end

      def default_headers
        {
          'Authorization' => "Bearer #{connection.access_token}",
          'Content-Type' => 'application/json',
          'Accept' => 'application/json'
        }
      end

      def get_contact_by_email(email)
        response = http_request(:get, "#{api_base}/contacts?email=#{CGI.escape(email)}&include=custom_fields,list_memberships")

        if response.success? && response.body['contacts'].present?
          response.body['contacts'].first
        else
          nil
        end
      end

      def update_existing_contact(contact_id, customer, list_id = nil)
        body = build_contact_body(customer, list_id, for_update: true)

        response = http_request(:put, "#{api_base}/contacts/#{contact_id}", body: body)

        if response.success?
          customer.update_columns(
            constant_contact_id: contact_id,
            email_marketing_synced_at: Time.current
          )
          { success: true, contact_id: contact_id, action: 'updated' }
        else
          add_error("Failed to update contact #{customer.email}: #{response.error_message}")
          { success: false, error: response.error_message }
        end
      end

      def build_contact_body(customer, list_id = nil, for_update: false)
        # Check both global unsubscribe (unsubscribed_at) AND marketing opt-out (email_marketing_opt_out)
        opted_out = customer.unsubscribed_from_emails? || customer.email_marketing_opt_out?
        body = {
          email_address: {
            address: customer.email,
            permission_to_send: opted_out ? 'unsubscribed' : 'implicit'
          },
          first_name: customer.first_name.to_s,
          last_name: customer.last_name.to_s,
          update_source: 'Account'
        }

        # Add phone numbers
        if customer.phone.present?
          body[:phone_numbers] = [
            { phone_number: customer.phone, kind: 'mobile' }
          ]
        end

        # Add list membership
        if list_id
          body[:list_memberships] = [list_id]
        end

        # Add custom fields based on connection config
        if connection.field_mappings.present?
          custom_fields = []
          connection.field_mappings.each do |local_field, cc_field|
            value = customer.try(local_field)
            if value.present?
              custom_fields << { custom_field_id: cc_field, value: value.to_s }
            end
          end
          body[:custom_fields] = custom_fields if custom_fields.present?
        end

        body
      end
    end
  end
end
