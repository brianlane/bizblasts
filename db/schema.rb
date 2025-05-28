# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_05_28_195948) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_admin_comments", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.boolean "primary"
    t.integer "position"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "booking_policies", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.integer "cancellation_window_mins"
    t.integer "buffer_time_mins"
    t.integer "max_daily_bookings"
    t.integer "max_advance_days"
    t.jsonb "intake_fields"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "min_duration_mins"
    t.integer "max_duration_mins"
    t.index ["business_id"], name: "index_booking_policies_on_business_id"
  end

  create_table "booking_product_add_ons", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "product_variant_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_booking_product_add_ons_on_booking_id"
    t.index ["product_variant_id"], name: "index_booking_product_add_ons_on_product_variant_id"
  end

  create_table "bookings", force: :cascade do |t|
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.integer "status", default: 0
    t.text "notes"
    t.bigint "service_id"
    t.bigint "staff_member_id"
    t.bigint "tenant_customer_id"
    t.bigint "business_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "promotion_id"
    t.decimal "original_amount", precision: 10, scale: 2
    t.decimal "discount_amount", precision: 10, scale: 2
    t.decimal "amount", precision: 10, scale: 2
    t.text "cancellation_reason"
    t.index ["business_id"], name: "index_bookings_on_business_id"
    t.index ["promotion_id"], name: "index_bookings_on_promotion_id"
    t.index ["service_id"], name: "index_bookings_on_service_id"
    t.index ["staff_member_id"], name: "index_bookings_on_staff_member_id"
    t.index ["start_time", "end_time"], name: "index_bookings_on_start_time_and_end_time", using: :gist
    t.index ["start_time"], name: "index_bookings_on_start_time"
    t.index ["status"], name: "index_bookings_on_status"
    t.index ["tenant_customer_id"], name: "index_bookings_on_tenant_customer_id"
  end

  create_table "businesses", force: :cascade do |t|
    t.string "name", null: false
    t.string "industry"
    t.string "phone"
    t.string "email"
    t.string "website"
    t.string "address"
    t.string "city"
    t.string "state"
    t.string "zip"
    t.text "description"
    t.string "time_zone", default: "UTC"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "service_template_id"
    t.string "tier"
    t.string "hostname"
    t.string "host_type"
    t.string "subdomain"
    t.jsonb "hours"
    t.string "stripe_customer_id"
    t.boolean "show_services_section", default: true, null: false
    t.boolean "show_products_section", default: true, null: false
    t.boolean "show_estimate_page", default: true, null: false
    t.string "facebook_url"
    t.string "twitter_url"
    t.string "instagram_url"
    t.string "pinterest_url"
    t.string "linkedin_url"
    t.string "tiktok_url"
    t.string "youtube_url"
    t.string "stripe_account_id"
    t.string "status", default: "pending", null: false
    t.boolean "payment_reminders_enabled", default: false, null: false
    t.index ["host_type"], name: "index_businesses_on_host_type"
    t.index ["hostname"], name: "index_businesses_on_hostname", unique: true
    t.index ["name"], name: "index_businesses_on_name"
    t.index ["service_template_id"], name: "index_businesses_on_service_template_id"
    t.index ["status"], name: "index_businesses_on_status"
    t.index ["stripe_account_id"], name: "index_businesses_on_stripe_account_id", unique: true
    t.index ["stripe_customer_id"], name: "index_businesses_on_stripe_customer_id", unique: true
  end

  create_table "campaign_recipients", force: :cascade do |t|
    t.bigint "marketing_campaign_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.datetime "sent_at"
    t.boolean "opened", default: false
    t.boolean "clicked", default: false
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["marketing_campaign_id"], name: "index_campaign_recipients_on_marketing_campaign_id"
    t.index ["tenant_customer_id"], name: "index_campaign_recipients_on_tenant_customer_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_categories_on_business_id"
    t.index ["name", "business_id"], name: "index_categories_on_name_and_business_id", unique: true
  end

  create_table "client_businesses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_client_businesses_on_business_id"
    t.index ["user_id", "business_id"], name: "index_client_businesses_on_user_id_and_business_id", unique: true
    t.index ["user_id"], name: "index_client_businesses_on_user_id"
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "integration_credentials", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.integer "provider"
    t.jsonb "config"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_integration_credentials_on_business_id"
  end

  create_table "integrations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.integer "kind", null: false
    t.jsonb "config"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_integrations_on_business_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.string "invoice_number", null: false
    t.datetime "due_date"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.integer "status", default: 0
    t.bigint "booking_id"
    t.bigint "tenant_customer_id", null: false
    t.bigint "business_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "promotion_id"
    t.decimal "original_amount", precision: 10, scale: 2
    t.decimal "discount_amount", precision: 10, scale: 2
    t.bigint "shipping_method_id"
    t.bigint "tax_rate_id"
    t.bigint "order_id"
    t.string "guest_access_token"
    t.index ["booking_id"], name: "index_invoices_on_booking_id"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number"
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["promotion_id"], name: "index_invoices_on_promotion_id"
    t.index ["shipping_method_id"], name: "index_invoices_on_shipping_method_id"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["tax_rate_id"], name: "index_invoices_on_tax_rate_id"
    t.index ["tenant_customer_id"], name: "index_invoices_on_tenant_customer_id"
  end

  create_table "line_items", force: :cascade do |t|
    t.string "lineable_type", null: false
    t.bigint "lineable_id", null: false
    t.bigint "product_variant_id"
    t.integer "quantity", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "service_id"
    t.bigint "staff_member_id"
    t.index ["lineable_type", "lineable_id"], name: "index_line_items_on_lineable"
    t.index ["product_variant_id"], name: "index_line_items_on_product_variant_id"
    t.index ["service_id"], name: "index_line_items_on_service_id"
    t.index ["staff_member_id"], name: "index_line_items_on_staff_member_id"
  end

  create_table "locations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "name"
    t.string "address"
    t.string "city"
    t.string "state"
    t.string "zip"
    t.jsonb "hours"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_locations_on_business_id"
  end

  create_table "marketing_campaigns", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "campaign_type", default: 0
    t.datetime "start_date"
    t.datetime "end_date"
    t.boolean "active", default: true
    t.integer "status", default: 0
    t.text "content"
    t.jsonb "settings"
    t.bigint "business_id", null: false
    t.bigint "promotion_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.index ["business_id"], name: "index_marketing_campaigns_on_business_id"
    t.index ["name", "business_id"], name: "index_marketing_campaigns_on_name_and_business_id", unique: true
    t.index ["promotion_id"], name: "index_marketing_campaigns_on_promotion_id"
  end

  create_table "notification_templates", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "event_type"
    t.integer "channel"
    t.string "subject"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_notification_templates_on_business_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "tenant_customer_id"
    t.string "order_number", null: false
    t.string "status", default: "pending_payment", null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.decimal "shipping_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "shipping_method_id"
    t.bigint "tax_rate_id"
    t.bigint "business_id"
    t.text "shipping_address"
    t.text "billing_address"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order_type", default: 0
    t.bigint "booking_id"
    t.index ["booking_id"], name: "index_orders_on_booking_id"
    t.index ["business_id"], name: "index_orders_on_business_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["shipping_method_id"], name: "index_orders_on_shipping_method_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["tax_rate_id"], name: "index_orders_on_tax_rate_id"
    t.index ["tenant_customer_id"], name: "index_orders_on_tenant_customer_id"
    t.check_constraint "status::text = ANY (ARRAY['pending_payment'::character varying, 'paid'::character varying, 'cancelled'::character varying, 'shipped'::character varying, 'refunded'::character varying, 'processing'::character varying, 'business_deleted'::character varying]::text[])", name: "status_enum_check"
  end

  create_table "page_sections", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.integer "section_type"
    t.text "content"
    t.integer "position"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["page_id"], name: "index_page_sections_on_page_id"
  end

  create_table "pages", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "title"
    t.string "slug"
    t.integer "page_type"
    t.boolean "published"
    t.datetime "published_at"
    t.integer "menu_order"
    t.boolean "show_in_menu"
    t.string "meta_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_pages_on_business_id"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "business_id"
    t.bigint "invoice_id"
    t.bigint "order_id"
    t.bigint "tenant_customer_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "platform_fee_amount", precision: 10, scale: 2, null: false
    t.decimal "stripe_fee_amount", precision: 10, scale: 2, null: false
    t.decimal "business_amount", precision: 10, scale: 2, null: false
    t.string "stripe_payment_intent_id"
    t.string "stripe_charge_id"
    t.string "stripe_customer_id"
    t.string "stripe_transfer_id"
    t.string "payment_method", default: "card"
    t.integer "status", default: 0
    t.datetime "paid_at"
    t.text "failure_reason"
    t.decimal "refunded_amount", precision: 10, scale: 2, default: "0.0"
    t.text "refund_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "paid_at"], name: "index_payments_on_business_id_and_paid_at"
    t.index ["business_id", "status"], name: "index_payments_on_business_id_and_status"
    t.index ["business_id"], name: "index_payments_on_business_id"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["stripe_charge_id"], name: "index_payments_on_stripe_charge_id"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
    t.index ["tenant_customer_id"], name: "index_payments_on_tenant_customer_id"
  end

  create_table "product_service_add_ons", force: :cascade do |t|
    t.bigint "product_id"
    t.bigint "service_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.decimal "price_modifier", precision: 10, scale: 2
    t.integer "stock_quantity", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reserved_quantity"
    t.string "sku"
    t.jsonb "options"
    t.index ["product_id"], name: "index_product_variants_on_product_id"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.boolean "active", default: true
    t.boolean "featured", default: false
    t.bigint "category_id"
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "product_type"
    t.integer "stock_quantity", default: 0, null: false
    t.index ["active"], name: "index_products_on_active"
    t.index ["business_id"], name: "index_products_on_business_id"
    t.index ["category_id"], name: "index_products_on_category_id"
    t.index ["featured"], name: "index_products_on_featured"
  end

  create_table "promotion_redemptions", force: :cascade do |t|
    t.bigint "promotion_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.bigint "booking_id"
    t.bigint "invoice_id"
    t.datetime "redeemed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_promotion_redemptions_on_booking_id"
    t.index ["invoice_id"], name: "index_promotion_redemptions_on_invoice_id"
    t.index ["promotion_id"], name: "index_promotion_redemptions_on_promotion_id"
    t.index ["tenant_customer_id"], name: "index_promotion_redemptions_on_tenant_customer_id"
  end

  create_table "promotions", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.text "description"
    t.integer "discount_type", default: 0
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.datetime "start_date"
    t.datetime "end_date"
    t.integer "usage_limit"
    t.integer "current_usage", default: 0
    t.boolean "active", default: true
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_promotions_on_business_id"
    t.index ["code", "business_id"], name: "index_promotions_on_code_and_business_id", unique: true
  end

  create_table "service_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true
    t.jsonb "structure"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "template_type", default: 0, null: false
    t.integer "industry"
    t.index ["active"], name: "index_service_templates_on_active"
    t.index ["industry"], name: "index_service_templates_on_industry"
    t.index ["name"], name: "index_service_templates_on_name"
    t.index ["template_type"], name: "index_service_templates_on_template_type"
  end

  create_table "services", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "duration", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.boolean "active", default: true
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "featured"
    t.jsonb "availability_settings"
    t.integer "service_type"
    t.integer "min_bookings"
    t.integer "max_bookings"
    t.integer "spots"
    t.index ["business_id"], name: "index_services_on_business_id"
    t.index ["name", "business_id"], name: "index_services_on_name_and_business_id", unique: true
  end

  create_table "services_staff_members", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.bigint "staff_member_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "staff_member_id"], name: "index_services_staff_members_uniqueness", unique: true
    t.index ["service_id"], name: "index_services_staff_members_on_service_id"
    t.index ["staff_member_id"], name: "index_services_staff_members_on_staff_member_id"
  end

  create_table "shipping_methods", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "cost", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "active", default: true
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_shipping_methods_on_active"
    t.index ["business_id"], name: "index_shipping_methods_on_business_id"
    t.index ["name", "business_id"], name: "index_shipping_methods_on_name_and_business_id", unique: true
  end

  create_table "sms_messages", force: :cascade do |t|
    t.bigint "marketing_campaign_id"
    t.bigint "tenant_customer_id", null: false
    t.bigint "booking_id"
    t.string "phone_number", null: false
    t.text "content", null: false
    t.integer "status", default: 0, null: false
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "external_id"
    t.index ["booking_id"], name: "index_sms_messages_on_booking_id"
    t.index ["external_id"], name: "index_sms_messages_on_external_id"
    t.index ["marketing_campaign_id"], name: "index_sms_messages_on_marketing_campaign_id"
    t.index ["status"], name: "index_sms_messages_on_status"
    t.index ["tenant_customer_id"], name: "index_sms_messages_on_tenant_customer_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "staff_assignments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "service_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id"], name: "index_staff_assignments_on_service_id"
    t.index ["user_id"], name: "index_staff_assignments_on_user_id"
  end

  create_table "staff_members", force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.text "bio"
    t.boolean "active", default: true
    t.bigint "business_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status"
    t.string "position"
    t.string "specialties", default: [], array: true
    t.string "timezone", default: "UTC"
    t.jsonb "availability"
    t.string "color"
    t.string "photo_url"
    t.index ["business_id"], name: "index_staff_members_on_business_id"
    t.index ["user_id"], name: "index_staff_members_on_user_id"
  end

  create_table "stock_reservations", force: :cascade do |t|
    t.bigint "product_variant_id"
    t.bigint "order_id"
    t.integer "quantity"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "plan_name", null: false
    t.string "stripe_subscription_id", null: false
    t.string "status", null: false
    t.datetime "current_period_end", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_subscriptions_on_business_id", unique: true
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
  end

  create_table "tax_rates", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "rate", precision: 10, scale: 4, null: false
    t.string "region"
    t.boolean "applies_to_shipping", default: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_tax_rates_on_business_id"
    t.index ["name", "business_id"], name: "index_tax_rates_on_name_and_business_id", unique: true
  end

  create_table "tenant_customers", force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.string "address"
    t.text "notes"
    t.bigint "business_id", null: false
    t.datetime "last_appointment"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_customer_id"
    t.index ["business_id"], name: "index_tenant_customers_on_business_id"
    t.index ["email", "business_id"], name: "index_tenant_customers_on_email_and_business_id", unique: true
    t.index ["stripe_customer_id"], name: "index_tenant_customers_on_stripe_customer_id", unique: true
  end

  create_table "test_models", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "role", default: 3
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "business_id"
    t.bigint "staff_member_id"
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.jsonb "notification_preferences"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "booking_policies", "businesses", on_delete: :cascade
  add_foreign_key "booking_product_add_ons", "bookings", on_delete: :cascade
  add_foreign_key "booking_product_add_ons", "product_variants"
  add_foreign_key "bookings", "businesses", on_delete: :cascade
  add_foreign_key "bookings", "promotions", on_delete: :nullify
  add_foreign_key "bookings", "services", on_delete: :nullify
  add_foreign_key "bookings", "staff_members", on_delete: :nullify
  add_foreign_key "bookings", "tenant_customers", on_delete: :nullify
  add_foreign_key "businesses", "service_templates"
  add_foreign_key "campaign_recipients", "marketing_campaigns"
  add_foreign_key "campaign_recipients", "tenant_customers"
  add_foreign_key "categories", "businesses", on_delete: :cascade
  add_foreign_key "client_businesses", "businesses", on_delete: :cascade
  add_foreign_key "client_businesses", "users"
  add_foreign_key "integration_credentials", "businesses", on_delete: :cascade
  add_foreign_key "integrations", "businesses", on_delete: :cascade
  add_foreign_key "invoices", "bookings", on_delete: :nullify
  add_foreign_key "invoices", "businesses", on_delete: :cascade
  add_foreign_key "invoices", "orders"
  add_foreign_key "invoices", "promotions"
  add_foreign_key "invoices", "shipping_methods"
  add_foreign_key "invoices", "tax_rates"
  add_foreign_key "invoices", "tenant_customers", on_delete: :cascade
  add_foreign_key "line_items", "product_variants"
  add_foreign_key "line_items", "services", on_delete: :nullify
  add_foreign_key "line_items", "staff_members", on_delete: :nullify
  add_foreign_key "locations", "businesses", on_delete: :cascade
  add_foreign_key "marketing_campaigns", "businesses", on_delete: :cascade
  add_foreign_key "marketing_campaigns", "promotions"
  add_foreign_key "notification_templates", "businesses", on_delete: :cascade
  add_foreign_key "orders", "bookings", on_delete: :nullify
  add_foreign_key "orders", "businesses", on_delete: :cascade
  add_foreign_key "orders", "shipping_methods"
  add_foreign_key "orders", "tax_rates"
  add_foreign_key "orders", "tenant_customers", on_delete: :nullify
  add_foreign_key "page_sections", "pages"
  add_foreign_key "pages", "businesses", on_delete: :cascade
  add_foreign_key "payments", "businesses", on_delete: :cascade
  add_foreign_key "payments", "invoices", on_delete: :nullify
  add_foreign_key "payments", "orders", on_delete: :nullify
  add_foreign_key "payments", "tenant_customers", on_delete: :nullify
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "businesses", on_delete: :cascade
  add_foreign_key "products", "categories"
  add_foreign_key "promotion_redemptions", "bookings", on_delete: :cascade
  add_foreign_key "promotion_redemptions", "invoices"
  add_foreign_key "promotion_redemptions", "promotions"
  add_foreign_key "promotion_redemptions", "tenant_customers"
  add_foreign_key "promotions", "businesses", on_delete: :cascade
  add_foreign_key "services", "businesses", on_delete: :cascade
  add_foreign_key "services_staff_members", "services", on_delete: :cascade
  add_foreign_key "services_staff_members", "staff_members", on_delete: :cascade
  add_foreign_key "shipping_methods", "businesses", on_delete: :cascade
  add_foreign_key "sms_messages", "bookings", on_delete: :cascade
  add_foreign_key "sms_messages", "marketing_campaigns"
  add_foreign_key "sms_messages", "tenant_customers"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "staff_assignments", "services"
  add_foreign_key "staff_assignments", "users"
  add_foreign_key "staff_members", "businesses", on_delete: :cascade
  add_foreign_key "staff_members", "users", on_delete: :nullify
  add_foreign_key "stock_reservations", "orders"
  add_foreign_key "stock_reservations", "product_variants", on_delete: :cascade
  add_foreign_key "subscriptions", "businesses", on_delete: :cascade
  add_foreign_key "tax_rates", "businesses", on_delete: :cascade
  add_foreign_key "tenant_customers", "businesses", on_delete: :cascade
  add_foreign_key "users", "businesses", on_delete: :cascade
  add_foreign_key "users", "staff_members"
end
