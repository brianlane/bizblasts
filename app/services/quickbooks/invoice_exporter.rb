# frozen_string_literal: true

module Quickbooks
  class InvoiceExporter
    DEFAULT_ITEM_NAME = 'BizBlasts Sales'.freeze
    DEFAULT_CUSTOMER_NAME = 'BizBlasts Customers'.freeze

    def initialize(business:, connection:)
      @business = business
      @connection = connection
      @oauth_handler = Quickbooks::OauthHandler.new
    end

    def export_invoices!(invoices:, export_payments: false)
      ensure_fresh_token!
      client = Quickbooks::Client.new(@connection)

      item_id = ensure_default_item_id!(client)

      results = {
        exported: 0,
        skipped_already_exported: 0,
        failed: 0,
        payments_exported: 0,
        payments_failed: 0,
        failures: []
      }

      invoices.find_each do |invoice|
        begin
          customer = invoice.tenant_customer
          customer_id = ensure_customer_id!(client, customer)

          qb_invoice_id, created_or_updated = ensure_invoice_in_qbo!(
            client: client,
            invoice: invoice,
            customer_id: customer_id,
            item_id: item_id
          )

          if created_or_updated == :skipped
            results[:skipped_already_exported] += 1
          else
            results[:exported] += 1
          end

          if export_payments && invoice.paid? && qb_invoice_id.present?
            pay_results = export_payments_for_invoice!(
              client: client,
              invoice: invoice,
              qb_invoice_id: qb_invoice_id,
              qb_customer_id: customer_id
            )
            results[:payments_exported] += pay_results[:exported]
            results[:payments_failed] += pay_results[:failed]
            results[:failures].concat(pay_results[:failures]) if pay_results[:failures].present?
          end
        rescue => e
          results[:failed] += 1
          results[:failures] << {
            invoice_id: invoice.id,
            invoice_number: invoice.invoice_number,
            error: e.message
          }

          begin
            invoice.update!(quickbooks_export_status: Invoice.quickbooks_export_statuses[:export_failed])
          rescue
            nil
          end
        end
      end

      results
    end

    private

    def ensure_fresh_token!
      return unless @connection.needs_refresh?

      ok = @oauth_handler.refresh_token(@connection)
      raise "QuickBooks token refresh failed: #{@oauth_handler.errors.full_messages.to_sentence}" unless ok
    end

    def ensure_customer_id!(client, tenant_customer)
      strategy = @connection.config.fetch('customer_strategy', 'per_customer').to_s
      if strategy == 'single'
        return ensure_default_customer_id!(client)
      end

      return tenant_customer.quickbooks_customer_id if tenant_customer.quickbooks_customer_id.present?

      display_name = tenant_customer.full_name.to_s.strip
      display_name = tenant_customer.email.to_s.strip if display_name.blank?

      # Try to find by DisplayName first (idempotency).
      begin
        found = client.query("select Id, DisplayName from Customer where DisplayName = '#{escape_qbo_string(display_name)}' maxresults 1")
        existing_id = found.dig('QueryResponse', 'Customer', 0, 'Id')
        if existing_id.present?
          tenant_customer.update!(quickbooks_customer_id: existing_id)
          return existing_id
        end
      rescue
        # ignore lookup errors and attempt create
      end

      payload = {
        DisplayName: display_name,
        PrimaryEmailAddr: tenant_customer.email.present? ? { Address: tenant_customer.email } : nil
      }.compact

      created = client.post("/v3/company/#{@connection.realm_id}/customer", body: payload, query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })
      qb_id = created.dig('Customer', 'Id')
      raise "Missing Customer Id in response" if qb_id.blank?

      tenant_customer.update!(quickbooks_customer_id: qb_id)
      qb_id
    end

    def ensure_default_item_id!(client)
      existing = @connection.config['default_sales_item_id'].to_s
      return existing if existing.present?

      income_account_id = @connection.config['income_account_id'].to_s
      if income_account_id.blank?
        income_account_id = find_income_account_id!(client)
        @connection.update!(config: @connection.config.merge('income_account_id' => income_account_id))
      end

      item_name = @connection.config['default_sales_item_name'].to_s.presence || DEFAULT_ITEM_NAME
      payload = {
        Name: item_name,
        Type: 'Service',
        IncomeAccountRef: { value: income_account_id }
      }

      created = client.post("/v3/company/#{@connection.realm_id}/item", body: payload, query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })
      item_id = created.dig('Item', 'Id')
      raise "Missing Item Id in response" if item_id.blank?

      @connection.update!(config: @connection.config.merge('default_sales_item_id' => item_id))
      item_id
    rescue Quickbooks::RequestError => e
      # If item already exists with that name, try to look it up.
      begin
        item_name = @connection.config['default_sales_item_name'].to_s.presence || DEFAULT_ITEM_NAME
        found = client.query("select Id, Name from Item where Name = '#{escape_qbo_string(item_name)}' maxresults 1")
        item_id = found.dig('QueryResponse', 'Item', 0, 'Id')
        raise e if item_id.blank?

        @connection.update!(config: @connection.config.merge('default_sales_item_id' => item_id))
        item_id
      rescue
        raise e
      end
    end

    def ensure_default_customer_id!(client)
      existing = @connection.config['default_customer_id'].to_s
      return existing if existing.present?

      payload = { DisplayName: DEFAULT_CUSTOMER_NAME }
      created = client.post("/v3/company/#{@connection.realm_id}/customer", body: payload, query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })
      qb_id = created.dig('Customer', 'Id')
      raise "Missing Customer Id in response" if qb_id.blank?

      @connection.update!(config: @connection.config.merge('default_customer_id' => qb_id))
      qb_id
    rescue Quickbooks::RequestError => e
      begin
        found = client.query("select Id, DisplayName from Customer where DisplayName = '#{escape_qbo_string(DEFAULT_CUSTOMER_NAME)}' maxresults 1")
        qb_id = found.dig('QueryResponse', 'Customer', 0, 'Id')
        raise e if qb_id.blank?

        @connection.update!(config: @connection.config.merge('default_customer_id' => qb_id))
        qb_id
      rescue
        raise e
      end
    end

    def find_income_account_id!(client)
      resp = client.query("select Id, Name from Account where AccountType = 'Income' maxresults 1")
      id = resp.dig('QueryResponse', 'Account', 0, 'Id')
      raise 'No Income account found in QuickBooks. Please create one and try again.' if id.blank?

      id
    end

    def ensure_invoice_in_qbo!(client:, invoice:, customer_id:, item_id:)
      # If we already exported the invoice, don't re-create it.
      if invoice.quickbooks_invoice_id.present? && invoice.quickbooks_export_exported?
        return [invoice.quickbooks_invoice_id, :skipped]
      end

      # If there is no stored QBO id, attempt lookup by DocNumber for idempotency.
      if invoice.quickbooks_invoice_id.blank?
        found = find_invoice_by_doc_number(client, invoice.invoice_number.to_s)
        if found[:id].present?
          invoice.update!(
            quickbooks_invoice_id: found[:id],
            quickbooks_exported_at: Time.current,
            quickbooks_export_status: Invoice.quickbooks_export_statuses[:exported]
          )

          if update_existing_invoices?
            update_invoice_in_qbo!(client: client, qb_invoice_id: found[:id], sync_token: found[:sync_token], invoice: invoice, customer_id: customer_id, item_id: item_id)
            return [found[:id], :updated]
          end

          return [found[:id], :found]
        end
      end

      payload = build_invoice_payload(invoice: invoice, customer_id: customer_id, item_id: item_id)

      if update_existing_invoices? && invoice.quickbooks_invoice_id.present?
        # Update existing invoice by ID if we already have one.
        existing = fetch_invoice_sync_token(client, invoice.quickbooks_invoice_id)
        update_invoice_in_qbo!(client: client, qb_invoice_id: invoice.quickbooks_invoice_id, sync_token: existing[:sync_token], invoice: invoice, customer_id: customer_id, item_id: item_id)
        invoice.update!(
          quickbooks_exported_at: Time.current,
          quickbooks_export_status: Invoice.quickbooks_export_statuses[:exported]
        )
        return [invoice.quickbooks_invoice_id, :updated]
      end

      created = client.post("/v3/company/#{@connection.realm_id}/invoice", body: payload, query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })

      qb_id = created.dig('Invoice', 'Id')
      raise "Missing Invoice Id in response" if qb_id.blank?

      invoice.update!(
        quickbooks_invoice_id: qb_id,
        quickbooks_exported_at: Time.current,
        quickbooks_export_status: Invoice.quickbooks_export_statuses[:exported]
      )

      [qb_id, :created]
    end

    def find_invoice_by_doc_number(client, doc_number)
      resp = client.query("select Id, DocNumber, SyncToken from Invoice where DocNumber = '#{escape_qbo_string(doc_number)}' maxresults 1")
      inv = resp.dig('QueryResponse', 'Invoice', 0) || {}
      { id: inv['Id'], sync_token: inv['SyncToken'] }
    rescue
      { id: nil, sync_token: nil }
    end

    def fetch_invoice_sync_token(client, qb_invoice_id)
      resp = client.get("/v3/company/#{@connection.realm_id}/invoice/#{qb_invoice_id}", query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })
      token = resp.dig('Invoice', 'SyncToken')
      { sync_token: token }
    end

    def update_invoice_in_qbo!(client:, qb_invoice_id:, sync_token:, invoice:, customer_id:, item_id:)
      raise 'Missing SyncToken for QuickBooks invoice update' if sync_token.blank?

      amount = invoice.total_amount.to_f
      amount = 0.0 if amount.negative?

      update_payload = {
        sparse: true,
        Id: qb_invoice_id,
        SyncToken: sync_token,
        CustomerRef: { value: customer_id },
        Line: [
          {
            Amount: amount,
            DetailType: 'SalesItemLineDetail',
            Description: "BizBlasts Invoice ##{invoice.invoice_number}",
            SalesItemLineDetail: {
              ItemRef: { value: item_id },
              Qty: 1,
              UnitPrice: amount
            }
          }
        ]
      }

      client.post("/v3/company/#{@connection.realm_id}/invoice", body: update_payload, query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })
    end

    def export_payments_for_invoice!(client:, invoice:, qb_invoice_id:, qb_customer_id:)
      results = { exported: 0, failed: 0, failures: [] }

      invoice.payments.successful.where(quickbooks_payment_id: [nil, '']).find_each do |payment|
        begin
          payload = build_payment_payload(payment: payment, qb_invoice_id: qb_invoice_id, qb_customer_id: qb_customer_id)
          created = client.post("/v3/company/#{@connection.realm_id}/payment", body: payload, query: { minorversion: Quickbooks::Client::DEFAULT_MINORVERSION })
          qb_id = created.dig('Payment', 'Id')
          raise "Missing Payment Id in response" if qb_id.blank?

          payment.update!(quickbooks_payment_id: qb_id)
          results[:exported] += 1
        rescue => e
          results[:failed] += 1
          results[:failures] << {
            invoice_id: invoice.id,
            invoice_number: invoice.invoice_number,
            payment_id: payment.id,
            error: e.message
          }
        end
      end

      results
    end

    def build_payment_payload(payment:, qb_invoice_id:, qb_customer_id:)
      amount = payment.amount.to_f
      amount = 0.0 if amount.negative?

      txn_date = (payment.paid_at || payment.created_at)&.to_date&.iso8601 || Date.current.iso8601

      {
        CustomerRef: { value: qb_customer_id },
        TxnDate: txn_date,
        TotalAmt: amount,
        Line: [
          {
            Amount: amount,
            LinkedTxn: [
              {
                TxnId: qb_invoice_id,
                TxnType: 'Invoice'
              }
            ]
          }
        ]
      }
    end

    def update_existing_invoices?
      @connection.config.fetch('update_existing_invoices', false) == true || @connection.config.fetch('update_existing_invoices', 'false').to_s == '1'
    end

    def escape_qbo_string(str)
      str.to_s.gsub("'", "\\\\'")
    end

    def build_invoice_payload(invoice:, customer_id:, item_id:)
      amount = invoice.total_amount.to_f
      amount = 0.0 if amount.negative?

      {
        CustomerRef: { value: customer_id },
        DocNumber: invoice.invoice_number.to_s,
        TxnDate: invoice.created_at.to_date.iso8601,
        PrivateNote: "BizBlasts Invoice ##{invoice.invoice_number}",
        Line: [
          {
            Amount: amount,
            DetailType: 'SalesItemLineDetail',
            Description: "BizBlasts Invoice ##{invoice.invoice_number}",
            SalesItemLineDetail: {
              ItemRef: { value: item_id },
              Qty: 1,
              UnitPrice: amount
            }
          }
        ]
      }
    end
  end
end
