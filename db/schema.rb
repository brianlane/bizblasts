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

ActiveRecord::Schema[8.0].define(version: 2025_05_14_152101) do
  # These are extensions that must be enabled in order to support this database
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
    t.bigint "service_id", null: false
    t.bigint "staff_member_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.bigint "business_id", null: false
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
    t.index ["host_type"], name: "index_businesses_on_host_type"
    t.index ["hostname"], name: "index_businesses_on_hostname", unique: true
    t.index ["name"], name: "index_businesses_on_name"
    t.index ["service_template_id"], name: "index_businesses_on_service_template_id"
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

  create_table "invoices", force: :cascade do |t|
    t.string "invoice_number", null: false
    t.datetime "due_date"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.integer "status", default: 0
    t.bigint "booking_id"
    t.bigint "tenant_customer_id", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "promotion_id"
    t.decimal "original_amount", precision: 10, scale: 2
    t.decimal "discount_amount", precision: 10, scale: 2
    t.bigint "shipping_method_id"
    t.bigint "tax_rate_id"
    t.index ["booking_id"], name: "index_invoices_on_booking_id"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number"
    t.index ["promotion_id"], name: "index_invoices_on_promotion_id"
    t.index ["shipping_method_id"], name: "index_invoices_on_shipping_method_id"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["tax_rate_id"], name: "index_invoices_on_tax_rate_id"
    t.index ["tenant_customer_id"], name: "index_invoices_on_tenant_customer_id"
  end

  create_table "line_items", force: :cascade do |t|
    t.string "lineable_type", null: false
    t.bigint "lineable_id", null: false
    t.bigint "product_variant_id", null: false
    t.integer "quantity", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lineable_type", "lineable_id"], name: "index_line_items_on_lineable"
    t.index ["product_variant_id"], name: "index_line_items_on_product_variant_id"
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

  create_table "orders", force: :cascade do |t|
    t.bigint "tenant_customer_id", null: false
    t.string "order_number", null: false
    t.string "status", default: "pending", null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.decimal "shipping_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "shipping_method_id"
    t.bigint "tax_rate_id"
    t.bigint "business_id", null: false
    t.text "shipping_address"
    t.text "billing_address"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order_type", default: 0
    t.index ["business_id"], name: "index_orders_on_business_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["shipping_method_id"], name: "index_orders_on_shipping_method_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["tax_rate_id"], name: "index_orders_on_tax_rate_id"
    t.index ["tenant_customer_id"], name: "index_orders_on_tenant_customer_id"
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

  create_table "solidus_stripe_customers", force: :cascade do |t|
    t.integer "payment_method_id", null: false
    t.string "source_type"
    t.integer "source_id"
    t.string "stripe_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_method_id", "source_type", "source_id"], name: "payment_method_and_source", unique: true
    t.index ["stripe_id"], name: "index_solidus_stripe_customers_on_stripe_id"
  end

  create_table "solidus_stripe_payment_intents", force: :cascade do |t|
    t.string "stripe_intent_id"
    t.integer "order_id", null: false
    t.integer "payment_method_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_solidus_stripe_payment_intents_on_order_id"
    t.index ["payment_method_id"], name: "index_solidus_stripe_payment_intents_on_payment_method_id"
  end

  create_table "solidus_stripe_payment_sources", force: :cascade do |t|
    t.integer "payment_method_id"
    t.string "stripe_payment_method_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "solidus_stripe_slug_entries", force: :cascade do |t|
    t.integer "payment_method_id", null: false
    t.string "slug", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["payment_method_id"], name: "index_solidus_stripe_slug_entries_on_payment_method_id"
    t.index ["slug"], name: "index_solidus_stripe_slug_entries_on_slug", unique: true
  end

  create_table "spree_addresses", id: :serial, force: :cascade do |t|
    t.string "firstname"
    t.string "lastname"
    t.string "address1"
    t.string "address2"
    t.string "city"
    t.string "zipcode"
    t.string "phone"
    t.string "state_name"
    t.string "alternative_phone"
    t.string "company"
    t.integer "state_id"
    t.integer "country_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "name"
    t.bigint "business_id"
    t.index ["business_id"], name: "index_spree_addresses_on_business_id"
    t.index ["country_id"], name: "index_spree_addresses_on_country_id"
    t.index ["firstname"], name: "index_addresses_on_firstname"
    t.index ["lastname"], name: "index_addresses_on_lastname"
    t.index ["name"], name: "index_spree_addresses_on_name"
    t.index ["state_id"], name: "index_spree_addresses_on_state_id"
  end

  create_table "spree_adjustment_reasons", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "code"
    t.boolean "active", default: true
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["active"], name: "index_spree_adjustment_reasons_on_active"
    t.index ["code"], name: "index_spree_adjustment_reasons_on_code"
  end

  create_table "spree_adjustments", id: :serial, force: :cascade do |t|
    t.string "source_type"
    t.integer "source_id"
    t.string "adjustable_type"
    t.integer "adjustable_id", null: false
    t.decimal "amount", precision: 10, scale: 2
    t.string "label"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "order_id", null: false
    t.boolean "included", default: false
    t.integer "adjustment_reason_id"
    t.boolean "finalized", default: false, null: false
    t.integer "promotion_code_id"
    t.boolean "eligible", default: true
    t.index ["adjustable_id", "adjustable_type"], name: "index_spree_adjustments_on_adjustable_id_and_adjustable_type"
    t.index ["adjustable_id"], name: "index_adjustments_on_order_id"
    t.index ["eligible"], name: "index_spree_adjustments_on_eligible"
    t.index ["order_id"], name: "index_spree_adjustments_on_order_id"
    t.index ["promotion_code_id"], name: "index_spree_adjustments_on_promotion_code_id"
    t.index ["source_id", "source_type"], name: "index_spree_adjustments_on_source_id_and_source_type"
  end

  create_table "spree_assets", id: :serial, force: :cascade do |t|
    t.string "viewable_type"
    t.integer "viewable_id"
    t.integer "attachment_width"
    t.integer "attachment_height"
    t.integer "attachment_file_size"
    t.integer "position"
    t.string "attachment_content_type"
    t.string "attachment_file_name"
    t.string "type", limit: 75
    t.datetime "attachment_updated_at", precision: nil
    t.text "alt"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["viewable_id"], name: "index_assets_on_viewable_id"
    t.index ["viewable_type", "type"], name: "index_assets_on_viewable_type_and_type"
  end

  create_table "spree_calculators", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "calculable_type"
    t.integer "calculable_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "preferences"
    t.index ["calculable_id", "calculable_type"], name: "index_spree_calculators_on_calculable_id_and_calculable_type"
    t.index ["id", "type"], name: "index_spree_calculators_on_id_and_type"
  end

  create_table "spree_cartons", id: :serial, force: :cascade do |t|
    t.string "number"
    t.string "external_number"
    t.integer "stock_location_id"
    t.integer "address_id"
    t.integer "shipping_method_id"
    t.string "tracking"
    t.datetime "shipped_at", precision: nil
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "imported_from_shipment_id"
    t.index ["external_number"], name: "index_spree_cartons_on_external_number"
    t.index ["imported_from_shipment_id"], name: "index_spree_cartons_on_imported_from_shipment_id", unique: true
    t.index ["number"], name: "index_spree_cartons_on_number", unique: true
    t.index ["stock_location_id"], name: "index_spree_cartons_on_stock_location_id"
  end

  create_table "spree_countries", id: :serial, force: :cascade do |t|
    t.string "iso_name"
    t.string "iso"
    t.string "iso3"
    t.string "name"
    t.integer "numcode"
    t.boolean "states_required", default: false
    t.datetime "updated_at"
    t.datetime "created_at"
    t.index ["iso"], name: "index_spree_countries_on_iso"
  end

  create_table "spree_credit_cards", id: :serial, force: :cascade do |t|
    t.string "month"
    t.string "year"
    t.string "cc_type"
    t.string "last_digits"
    t.string "gateway_customer_profile_id"
    t.string "gateway_payment_profile_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "name"
    t.integer "user_id"
    t.integer "payment_method_id"
    t.boolean "default", default: false, null: false
    t.integer "address_id"
    t.index ["payment_method_id"], name: "index_spree_credit_cards_on_payment_method_id"
    t.index ["user_id"], name: "index_spree_credit_cards_on_user_id"
  end

  create_table "spree_customer_returns", id: :serial, force: :cascade do |t|
    t.string "number"
    t.integer "stock_location_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
  end

  create_table "spree_inventory_units", id: :serial, force: :cascade do |t|
    t.string "state"
    t.integer "variant_id"
    t.integer "shipment_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean "pending", default: true
    t.integer "line_item_id"
    t.integer "carton_id"
    t.index ["carton_id"], name: "index_spree_inventory_units_on_carton_id"
    t.index ["line_item_id"], name: "index_spree_inventory_units_on_line_item_id"
    t.index ["shipment_id"], name: "index_inventory_units_on_shipment_id"
    t.index ["variant_id"], name: "index_inventory_units_on_variant_id"
  end

  create_table "spree_line_item_actions", id: :serial, force: :cascade do |t|
    t.integer "line_item_id", null: false
    t.integer "action_id", null: false
    t.integer "quantity", default: 0
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["action_id"], name: "index_spree_line_item_actions_on_action_id"
    t.index ["line_item_id"], name: "index_spree_line_item_actions_on_line_item_id"
  end

  create_table "spree_line_items", id: :serial, force: :cascade do |t|
    t.integer "variant_id"
    t.integer "order_id"
    t.integer "quantity", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.decimal "cost_price", precision: 10, scale: 2
    t.integer "tax_category_id"
    t.decimal "adjustment_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "additional_tax_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "promo_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "included_tax_total", precision: 10, scale: 2, default: "0.0", null: false
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.boolean "is_service", default: false, null: false
    t.index ["is_service"], name: "index_spree_line_items_on_is_service"
    t.index ["order_id"], name: "index_spree_line_items_on_order_id"
    t.index ["variant_id"], name: "index_spree_line_items_on_variant_id"
  end

  create_table "spree_log_entries", id: :serial, force: :cascade do |t|
    t.string "source_type"
    t.integer "source_id"
    t.text "details"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["source_id", "source_type"], name: "index_spree_log_entries_on_source_id_and_source_type"
  end

  create_table "spree_option_type_prototypes", id: :serial, force: :cascade do |t|
    t.integer "prototype_id"
    t.integer "option_type_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_option_types", id: :serial, force: :cascade do |t|
    t.string "name", limit: 100
    t.string "presentation", limit: 100
    t.integer "position", default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["position"], name: "index_spree_option_types_on_position"
  end

  create_table "spree_option_values", id: :serial, force: :cascade do |t|
    t.integer "position"
    t.string "name"
    t.string "presentation"
    t.integer "option_type_id", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["option_type_id"], name: "index_spree_option_values_on_option_type_id"
    t.index ["position"], name: "index_spree_option_values_on_position"
  end

  create_table "spree_option_values_variants", id: :serial, force: :cascade do |t|
    t.integer "variant_id"
    t.integer "option_value_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["variant_id", "option_value_id"], name: "index_option_values_variants_on_variant_id_and_option_value_id", unique: true
    t.index ["variant_id"], name: "index_spree_option_values_variants_on_variant_id"
  end

  create_table "spree_order_mutexes", id: :serial, force: :cascade do |t|
    t.integer "order_id", null: false
    t.datetime "created_at"
    t.index ["order_id"], name: "index_spree_order_mutexes_on_order_id", unique: true
  end

  create_table "spree_orders", id: :serial, force: :cascade do |t|
    t.string "number", limit: 32
    t.decimal "item_total", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "total", precision: 10, scale: 2, default: "0.0", null: false
    t.string "state"
    t.decimal "adjustment_total", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "user_id"
    t.datetime "completed_at", precision: nil
    t.integer "bill_address_id"
    t.integer "ship_address_id"
    t.decimal "payment_total", precision: 10, scale: 2, default: "0.0"
    t.string "shipment_state"
    t.string "payment_state"
    t.string "email"
    t.text "special_instructions"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "currency"
    t.string "last_ip_address"
    t.integer "created_by_id"
    t.decimal "shipment_total", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "additional_tax_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "promo_total", precision: 10, scale: 2, default: "0.0"
    t.string "channel", default: "spree"
    t.decimal "included_tax_total", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "item_count", default: 0
    t.integer "approver_id"
    t.datetime "approved_at", precision: nil
    t.boolean "confirmation_delivered", default: false
    t.string "guest_token"
    t.datetime "canceled_at", precision: nil
    t.integer "canceler_id"
    t.integer "store_id"
    t.string "approver_name"
    t.boolean "frontend_viewable", default: true, null: false
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.bigint "business_id"
    t.index ["approver_id"], name: "index_spree_orders_on_approver_id"
    t.index ["bill_address_id"], name: "index_spree_orders_on_bill_address_id"
    t.index ["business_id"], name: "index_spree_orders_on_business_id"
    t.index ["completed_at"], name: "index_spree_orders_on_completed_at"
    t.index ["created_by_id"], name: "index_spree_orders_on_created_by_id"
    t.index ["guest_token"], name: "index_spree_orders_on_guest_token"
    t.index ["number"], name: "index_spree_orders_on_number"
    t.index ["ship_address_id"], name: "index_spree_orders_on_ship_address_id"
    t.index ["user_id", "created_by_id"], name: "index_spree_orders_on_user_id_and_created_by_id"
    t.index ["user_id"], name: "index_spree_orders_on_user_id"
  end

  create_table "spree_orders_promotions", id: :serial, force: :cascade do |t|
    t.integer "order_id"
    t.integer "promotion_id"
    t.integer "promotion_code_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["order_id", "promotion_id"], name: "index_spree_orders_promotions_on_order_id_and_promotion_id"
    t.index ["promotion_code_id"], name: "index_spree_orders_promotions_on_promotion_code_id"
  end

  create_table "spree_payment_capture_events", id: :serial, force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, default: "0.0"
    t.integer "payment_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["payment_id"], name: "index_spree_payment_capture_events_on_payment_id"
  end

  create_table "spree_payment_methods", id: :serial, force: :cascade do |t|
    t.string "type"
    t.string "name"
    t.text "description"
    t.boolean "active", default: true
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean "auto_capture"
    t.text "preferences"
    t.string "preference_source"
    t.integer "position", default: 0
    t.boolean "available_to_users", default: true
    t.boolean "available_to_admin", default: true
    t.string "type_before_removal"
    t.bigint "business_id"
    t.index ["business_id"], name: "index_spree_payment_methods_on_business_id"
    t.index ["id", "type"], name: "index_spree_payment_methods_on_id_and_type"
  end

  create_table "spree_payments", id: :serial, force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "order_id"
    t.string "source_type"
    t.integer "source_id"
    t.integer "payment_method_id"
    t.string "state"
    t.string "response_code"
    t.string "avs_response"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "number"
    t.string "cvv_response_code"
    t.string "cvv_response_message"
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.index ["number"], name: "index_spree_payments_on_number", unique: true
    t.index ["order_id"], name: "index_spree_payments_on_order_id"
    t.index ["payment_method_id"], name: "index_spree_payments_on_payment_method_id"
    t.index ["source_id", "source_type"], name: "index_spree_payments_on_source_id_and_source_type"
  end

  create_table "spree_permission_sets", force: :cascade do |t|
    t.string "name"
    t.string "set"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "privilege"
    t.string "category"
  end

  create_table "spree_preferences", id: :serial, force: :cascade do |t|
    t.text "value"
    t.string "key"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["key"], name: "index_spree_preferences_on_key", unique: true
  end

  create_table "spree_prices", id: :serial, force: :cascade do |t|
    t.integer "variant_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "country_iso", limit: 2
    t.index ["country_iso"], name: "index_spree_prices_on_country_iso"
    t.index ["variant_id", "currency"], name: "index_spree_prices_on_variant_id_and_currency"
  end

  create_table "spree_product_option_types", id: :serial, force: :cascade do |t|
    t.integer "position"
    t.integer "product_id"
    t.integer "option_type_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["option_type_id"], name: "index_spree_product_option_types_on_option_type_id"
    t.index ["position"], name: "index_spree_product_option_types_on_position"
    t.index ["product_id"], name: "index_spree_product_option_types_on_product_id"
  end

  create_table "spree_product_promotion_rules", id: :serial, force: :cascade do |t|
    t.integer "product_id"
    t.integer "promotion_rule_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["product_id"], name: "index_products_promotion_rules_on_product_id"
    t.index ["promotion_rule_id"], name: "index_products_promotion_rules_on_promotion_rule_id"
  end

  create_table "spree_product_properties", id: :serial, force: :cascade do |t|
    t.string "value"
    t.integer "product_id"
    t.integer "property_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "position", default: 0
    t.index ["position"], name: "index_spree_product_properties_on_position"
    t.index ["product_id"], name: "index_product_properties_on_product_id"
    t.index ["property_id"], name: "index_spree_product_properties_on_property_id"
  end

  create_table "spree_products", id: :serial, force: :cascade do |t|
    t.string "name", default: "", null: false
    t.text "description"
    t.datetime "available_on", precision: nil
    t.datetime "deleted_at", precision: nil
    t.string "slug"
    t.text "meta_description"
    t.string "meta_keywords"
    t.integer "tax_category_id"
    t.integer "shipping_category_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean "promotionable", default: true
    t.string "meta_title"
    t.datetime "discontinue_on", precision: nil
    t.integer "primary_taxon_id"
    t.bigint "business_id"
    t.index ["available_on"], name: "index_spree_products_on_available_on"
    t.index ["business_id"], name: "index_spree_products_on_business_id"
    t.index ["deleted_at"], name: "index_spree_products_on_deleted_at"
    t.index ["name"], name: "index_spree_products_on_name"
    t.index ["primary_taxon_id"], name: "index_spree_products_on_primary_taxon_id"
    t.index ["slug"], name: "index_spree_products_on_slug", unique: true
  end

  create_table "spree_products_taxons", id: :serial, force: :cascade do |t|
    t.integer "product_id"
    t.integer "taxon_id"
    t.integer "position"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["position"], name: "index_spree_products_taxons_on_position"
    t.index ["product_id"], name: "index_spree_products_taxons_on_product_id"
    t.index ["taxon_id"], name: "index_spree_products_taxons_on_taxon_id"
  end

  create_table "spree_promotion_actions", id: :serial, force: :cascade do |t|
    t.integer "promotion_id"
    t.integer "position"
    t.string "type"
    t.datetime "deleted_at", precision: nil
    t.text "preferences"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["deleted_at"], name: "index_spree_promotion_actions_on_deleted_at"
    t.index ["id", "type"], name: "index_spree_promotion_actions_on_id_and_type"
    t.index ["promotion_id"], name: "index_spree_promotion_actions_on_promotion_id"
  end

  create_table "spree_promotion_categories", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "code"
  end

  create_table "spree_promotion_code_batches", id: :serial, force: :cascade do |t|
    t.integer "promotion_id", null: false
    t.string "base_code", null: false
    t.integer "number_of_codes", null: false
    t.string "email"
    t.string "error"
    t.string "state", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "join_characters", default: "_", null: false
    t.index ["promotion_id"], name: "index_spree_promotion_code_batches_on_promotion_id"
  end

  create_table "spree_promotion_codes", id: :serial, force: :cascade do |t|
    t.integer "promotion_id", null: false
    t.string "value", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "promotion_code_batch_id"
    t.index ["promotion_code_batch_id"], name: "index_spree_promotion_codes_on_promotion_code_batch_id"
    t.index ["promotion_id"], name: "index_spree_promotion_codes_on_promotion_id"
    t.index ["value"], name: "index_spree_promotion_codes_on_value", unique: true
  end

  create_table "spree_promotion_rule_taxons", id: :serial, force: :cascade do |t|
    t.integer "taxon_id"
    t.integer "promotion_rule_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["promotion_rule_id"], name: "index_spree_promotion_rule_taxons_on_promotion_rule_id"
    t.index ["taxon_id"], name: "index_spree_promotion_rule_taxons_on_taxon_id"
  end

  create_table "spree_promotion_rules", id: :serial, force: :cascade do |t|
    t.integer "promotion_id"
    t.string "type"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "preferences"
    t.index ["promotion_id"], name: "index_spree_promotion_rules_on_promotion_id"
  end

  create_table "spree_promotion_rules_stores", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "promotion_rule_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["promotion_rule_id"], name: "index_spree_promotion_rules_stores_on_promotion_rule_id"
    t.index ["store_id"], name: "index_spree_promotion_rules_stores_on_store_id"
  end

  create_table "spree_promotion_rules_users", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "promotion_rule_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["promotion_rule_id"], name: "index_promotion_rules_users_on_promotion_rule_id"
    t.index ["user_id"], name: "index_promotion_rules_users_on_user_id"
  end

  create_table "spree_promotions", id: :serial, force: :cascade do |t|
    t.string "description"
    t.datetime "expires_at", precision: nil
    t.datetime "starts_at", precision: nil
    t.string "name"
    t.string "type"
    t.integer "usage_limit"
    t.boolean "advertise", default: false
    t.string "path"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "promotion_category_id"
    t.integer "per_code_usage_limit"
    t.boolean "apply_automatically", default: false
    t.index ["advertise"], name: "index_spree_promotions_on_advertise"
    t.index ["apply_automatically"], name: "index_spree_promotions_on_apply_automatically"
    t.index ["expires_at"], name: "index_spree_promotions_on_expires_at"
    t.index ["id", "type"], name: "index_spree_promotions_on_id_and_type"
    t.index ["promotion_category_id"], name: "index_spree_promotions_on_promotion_category_id"
    t.index ["starts_at"], name: "index_spree_promotions_on_starts_at"
  end

  create_table "spree_properties", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "presentation", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_property_prototypes", id: :serial, force: :cascade do |t|
    t.integer "prototype_id"
    t.integer "property_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_prototype_taxons", id: :serial, force: :cascade do |t|
    t.integer "taxon_id"
    t.integer "prototype_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["prototype_id"], name: "index_spree_prototype_taxons_on_prototype_id"
    t.index ["taxon_id"], name: "index_spree_prototype_taxons_on_taxon_id"
  end

  create_table "spree_prototypes", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_refund_reasons", id: :serial, force: :cascade do |t|
    t.string "name"
    t.boolean "active", default: true
    t.boolean "mutable", default: true
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "code"
  end

  create_table "spree_refunds", id: :serial, force: :cascade do |t|
    t.integer "payment_id"
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "transaction_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "refund_reason_id"
    t.integer "reimbursement_id"
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.index ["payment_id"], name: "index_spree_refunds_on_payment_id"
    t.index ["refund_reason_id"], name: "index_refunds_on_refund_reason_id"
    t.index ["reimbursement_id"], name: "index_spree_refunds_on_reimbursement_id"
  end

  create_table "spree_reimbursement_credits", id: :serial, force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "reimbursement_id"
    t.integer "creditable_id"
    t.string "creditable_type"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_reimbursement_types", id: :serial, force: :cascade do |t|
    t.string "name"
    t.boolean "active", default: true
    t.boolean "mutable", default: true
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "type"
    t.index ["type"], name: "index_spree_reimbursement_types_on_type"
  end

  create_table "spree_reimbursements", id: :serial, force: :cascade do |t|
    t.string "number"
    t.string "reimbursement_status"
    t.integer "customer_return_id"
    t.integer "order_id"
    t.decimal "total", precision: 10, scale: 2
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["customer_return_id"], name: "index_spree_reimbursements_on_customer_return_id"
    t.index ["order_id"], name: "index_spree_reimbursements_on_order_id"
  end

  create_table "spree_return_authorizations", id: :serial, force: :cascade do |t|
    t.string "number"
    t.string "state"
    t.integer "order_id"
    t.text "memo"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "stock_location_id"
    t.integer "return_reason_id"
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.index ["return_reason_id"], name: "index_return_authorizations_on_return_authorization_reason_id"
  end

  create_table "spree_return_items", id: :serial, force: :cascade do |t|
    t.integer "return_authorization_id"
    t.integer "inventory_unit_id"
    t.integer "exchange_variant_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.decimal "amount", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "included_tax_total", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "additional_tax_total", precision: 12, scale: 4, default: "0.0", null: false
    t.string "reception_status"
    t.string "acceptance_status"
    t.integer "customer_return_id"
    t.integer "reimbursement_id"
    t.integer "exchange_inventory_unit_id"
    t.text "acceptance_status_errors"
    t.integer "preferred_reimbursement_type_id"
    t.integer "override_reimbursement_type_id"
    t.boolean "resellable", default: true, null: false
    t.integer "return_reason_id"
    t.index ["customer_return_id"], name: "index_return_items_on_customer_return_id"
    t.index ["exchange_inventory_unit_id"], name: "index_spree_return_items_on_exchange_inventory_unit_id"
  end

  create_table "spree_return_reasons", id: :serial, force: :cascade do |t|
    t.string "name"
    t.boolean "active", default: true
    t.boolean "mutable", default: true
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_role_permissions", force: :cascade do |t|
    t.bigint "role_id"
    t.bigint "permission_set_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_set_id"], name: "index_spree_role_permissions_on_permission_set_id"
    t.index ["role_id"], name: "index_spree_role_permissions_on_role_id"
  end

  create_table "spree_roles", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "description"
    t.index ["name"], name: "index_spree_roles_on_name", unique: true
  end

  create_table "spree_roles_users", id: :serial, force: :cascade do |t|
    t.integer "role_id"
    t.integer "user_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["role_id"], name: "index_spree_roles_users_on_role_id"
    t.index ["user_id", "role_id"], name: "index_spree_roles_users_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_spree_roles_users_on_user_id"
  end

  create_table "spree_shipments", id: :serial, force: :cascade do |t|
    t.string "tracking"
    t.string "number"
    t.decimal "cost", precision: 10, scale: 2, default: "0.0"
    t.datetime "shipped_at", precision: nil
    t.integer "order_id"
    t.string "state"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "stock_location_id"
    t.decimal "adjustment_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "additional_tax_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "promo_total", precision: 10, scale: 2, default: "0.0"
    t.decimal "included_tax_total", precision: 10, scale: 2, default: "0.0", null: false
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.index ["number"], name: "index_shipments_on_number"
    t.index ["order_id"], name: "index_spree_shipments_on_order_id"
    t.index ["stock_location_id"], name: "index_spree_shipments_on_stock_location_id"
  end

  create_table "spree_shipping_categories", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_shipping_method_categories", id: :serial, force: :cascade do |t|
    t.integer "shipping_method_id", null: false
    t.integer "shipping_category_id", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["shipping_category_id", "shipping_method_id"], name: "unique_spree_shipping_method_categories", unique: true
    t.index ["shipping_method_id"], name: "index_spree_shipping_method_categories_on_shipping_method_id"
  end

  create_table "spree_shipping_method_stock_locations", id: :serial, force: :cascade do |t|
    t.integer "shipping_method_id"
    t.integer "stock_location_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["shipping_method_id"], name: "shipping_method_id_spree_sm_sl"
    t.index ["stock_location_id"], name: "sstock_location_id_spree_sm_sl"
  end

  create_table "spree_shipping_method_zones", id: :serial, force: :cascade do |t|
    t.integer "shipping_method_id"
    t.integer "zone_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_shipping_methods", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "tracking_url"
    t.string "admin_name"
    t.integer "tax_category_id"
    t.string "code"
    t.boolean "available_to_all", default: true
    t.string "carrier"
    t.string "service_level"
    t.boolean "available_to_users", default: true
    t.bigint "business_id"
    t.index ["business_id"], name: "index_spree_shipping_methods_on_business_id"
    t.index ["tax_category_id"], name: "index_spree_shipping_methods_on_tax_category_id"
  end

  create_table "spree_shipping_rate_taxes", id: :serial, force: :cascade do |t|
    t.decimal "amount", precision: 8, scale: 2, default: "0.0", null: false
    t.integer "tax_rate_id"
    t.integer "shipping_rate_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shipping_rate_id"], name: "index_spree_shipping_rate_taxes_on_shipping_rate_id"
    t.index ["tax_rate_id"], name: "index_spree_shipping_rate_taxes_on_tax_rate_id"
  end

  create_table "spree_shipping_rates", id: :serial, force: :cascade do |t|
    t.integer "shipment_id"
    t.integer "shipping_method_id"
    t.boolean "selected", default: false
    t.decimal "cost", precision: 8, scale: 2, default: "0.0"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "tax_rate_id"
    t.index ["shipment_id", "shipping_method_id"], name: "spree_shipping_rates_join_index", unique: true
  end

  create_table "spree_state_changes", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "previous_state"
    t.integer "stateful_id"
    t.integer "user_id"
    t.string "stateful_type"
    t.string "next_state"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["stateful_id", "stateful_type"], name: "index_spree_state_changes_on_stateful_id_and_stateful_type"
    t.index ["user_id"], name: "index_spree_state_changes_on_user_id"
  end

  create_table "spree_states", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "abbr"
    t.integer "country_id"
    t.datetime "updated_at"
    t.datetime "created_at"
    t.index ["country_id"], name: "index_spree_states_on_country_id"
  end

  create_table "spree_stock_items", id: :serial, force: :cascade do |t|
    t.integer "stock_location_id"
    t.integer "variant_id"
    t.integer "count_on_hand", default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean "backorderable", default: false
    t.datetime "deleted_at", precision: nil
    t.index ["deleted_at"], name: "index_spree_stock_items_on_deleted_at"
    t.index ["stock_location_id", "variant_id"], name: "stock_item_by_loc_and_var_id"
    t.index ["stock_location_id"], name: "index_spree_stock_items_on_stock_location_id"
    t.index ["variant_id", "stock_location_id"], name: "index_spree_stock_items_on_variant_id_and_stock_location_id", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "spree_stock_locations", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean "default", default: false, null: false
    t.string "address1"
    t.string "address2"
    t.string "city"
    t.integer "state_id"
    t.string "state_name"
    t.integer "country_id"
    t.string "zipcode"
    t.string "phone"
    t.boolean "active", default: true
    t.boolean "backorderable_default", default: false
    t.boolean "propagate_all_variants", default: true
    t.string "admin_name"
    t.integer "position", default: 0
    t.boolean "restock_inventory", default: true, null: false
    t.boolean "fulfillable", default: true, null: false
    t.string "code"
    t.boolean "check_stock_on_transfer", default: true
    t.bigint "business_id"
    t.index ["business_id"], name: "index_spree_stock_locations_on_business_id"
    t.index ["country_id"], name: "index_spree_stock_locations_on_country_id"
    t.index ["state_id"], name: "index_spree_stock_locations_on_state_id"
  end

  create_table "spree_stock_movements", id: :serial, force: :cascade do |t|
    t.integer "stock_item_id"
    t.integer "quantity", default: 0
    t.string "action"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "originator_type"
    t.integer "originator_id"
    t.index ["stock_item_id"], name: "index_spree_stock_movements_on_stock_item_id"
  end

  create_table "spree_store_credit_categories", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "spree_store_credit_events", id: :serial, force: :cascade do |t|
    t.integer "store_credit_id", null: false
    t.string "action", null: false
    t.decimal "amount", precision: 8, scale: 2
    t.decimal "user_total_amount", precision: 8, scale: 2, default: "0.0", null: false
    t.string "authorization_code", null: false
    t.datetime "deleted_at", precision: nil
    t.string "originator_type"
    t.integer "originator_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.decimal "amount_remaining", precision: 8, scale: 2
    t.integer "store_credit_reason_id"
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.index ["deleted_at"], name: "index_spree_store_credit_events_on_deleted_at"
    t.index ["store_credit_id"], name: "index_spree_store_credit_events_on_store_credit_id"
  end

  create_table "spree_store_credit_reasons", force: :cascade do |t|
    t.string "name"
    t.boolean "active", default: true
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "spree_store_credit_types", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "priority"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["priority"], name: "index_spree_store_credit_types_on_priority"
  end

  create_table "spree_store_credits", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "category_id"
    t.integer "created_by_id"
    t.decimal "amount", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "amount_used", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "amount_authorized", precision: 8, scale: 2, default: "0.0", null: false
    t.string "currency"
    t.text "memo"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "type_id"
    t.datetime "invalidated_at", precision: nil
    t.index ["deleted_at"], name: "index_spree_store_credits_on_deleted_at"
    t.index ["type_id"], name: "index_spree_store_credits_on_type_id"
    t.index ["user_id"], name: "index_spree_store_credits_on_user_id"
  end

  create_table "spree_store_payment_methods", id: :serial, force: :cascade do |t|
    t.integer "store_id", null: false
    t.integer "payment_method_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_method_id"], name: "index_spree_store_payment_methods_on_payment_method_id"
    t.index ["store_id"], name: "index_spree_store_payment_methods_on_store_id"
  end

  create_table "spree_store_shipping_methods", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "shipping_method_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shipping_method_id"], name: "index_spree_store_shipping_methods_on_shipping_method_id"
    t.index ["store_id"], name: "index_spree_store_shipping_methods_on_store_id"
  end

  create_table "spree_stores", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.text "meta_description"
    t.text "meta_keywords"
    t.string "seo_title"
    t.string "mail_from_address"
    t.string "default_currency"
    t.string "code"
    t.boolean "default", default: false, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "cart_tax_country_iso"
    t.string "available_locales"
    t.string "bcc_email"
    t.bigint "business_id"
    t.index ["business_id"], name: "index_spree_stores_on_business_id"
    t.index ["code"], name: "index_spree_stores_on_code"
    t.index ["default"], name: "index_spree_stores_on_default"
  end

  create_table "spree_tax_categories", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.boolean "is_default", default: false
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "tax_code"
  end

  create_table "spree_tax_rate_tax_categories", id: :serial, force: :cascade do |t|
    t.integer "tax_category_id", null: false
    t.integer "tax_rate_id", null: false
    t.index ["tax_category_id"], name: "index_spree_tax_rate_tax_categories_on_tax_category_id"
    t.index ["tax_rate_id"], name: "index_spree_tax_rate_tax_categories_on_tax_rate_id"
  end

  create_table "spree_tax_rates", id: :serial, force: :cascade do |t|
    t.decimal "amount", precision: 8, scale: 5
    t.integer "zone_id"
    t.boolean "included_in_price", default: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "name"
    t.boolean "show_rate_in_label", default: true
    t.datetime "deleted_at", precision: nil
    t.datetime "starts_at", precision: nil
    t.datetime "expires_at", precision: nil
    t.integer "level", default: 0, null: false
    t.index ["deleted_at"], name: "index_spree_tax_rates_on_deleted_at"
    t.index ["zone_id"], name: "index_spree_tax_rates_on_zone_id"
  end

  create_table "spree_taxonomies", id: :serial, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "position", default: 0
    t.bigint "business_id"
    t.index ["business_id"], name: "index_spree_taxonomies_on_business_id"
    t.index ["position"], name: "index_spree_taxonomies_on_position"
  end

  create_table "spree_taxons", id: :serial, force: :cascade do |t|
    t.integer "parent_id"
    t.string "name", null: false
    t.string "permalink"
    t.integer "taxonomy_id"
    t.integer "lft"
    t.integer "rgt"
    t.string "icon_file_name"
    t.string "icon_content_type"
    t.integer "icon_file_size"
    t.datetime "icon_updated_at", precision: nil
    t.text "description"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "meta_title"
    t.string "meta_description"
    t.string "meta_keywords"
    t.integer "depth"
    t.index ["lft"], name: "index_spree_taxons_on_lft"
    t.index ["parent_id"], name: "index_taxons_on_parent_id"
    t.index ["permalink"], name: "index_taxons_on_permalink"
    t.index ["rgt"], name: "index_spree_taxons_on_rgt"
    t.index ["taxonomy_id"], name: "index_taxons_on_taxonomy_id"
  end

  create_table "spree_unit_cancels", id: :serial, force: :cascade do |t|
    t.integer "inventory_unit_id", null: false
    t.string "reason"
    t.string "created_by"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["inventory_unit_id"], name: "index_spree_unit_cancels_on_inventory_unit_id"
  end

  create_table "spree_user_addresses", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "address_id", null: false
    t.boolean "default", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "default_billing", default: false
    t.index ["address_id"], name: "index_spree_user_addresses_on_address_id"
    t.index ["user_id", "address_id"], name: "index_spree_user_addresses_on_user_id_and_address_id", unique: true
    t.index ["user_id"], name: "index_spree_user_addresses_on_user_id"
  end

  create_table "spree_user_stock_locations", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "stock_location_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["user_id"], name: "index_spree_user_stock_locations_on_user_id"
  end

  create_table "spree_users", id: :serial, force: :cascade do |t|
    t.string "encrypted_password", limit: 128
    t.string "password_salt", limit: 128
    t.string "email"
    t.string "remember_token"
    t.string "persistence_token"
    t.string "reset_password_token"
    t.string "perishable_token"
    t.integer "sign_in_count", default: 0, null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_request_at", precision: nil
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "login"
    t.integer "ship_address_id"
    t.integer "bill_address_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "customer_metadata", default: {}
    t.jsonb "admin_metadata", default: {}
    t.string "spree_api_key", limit: 48
    t.string "authentication_token"
    t.string "unlock_token"
    t.datetime "locked_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "deleted_at", precision: nil
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.index ["deleted_at"], name: "index_spree_users_on_deleted_at"
    t.index ["email"], name: "email_idx_unique", unique: true
    t.index ["reset_password_token"], name: "index_spree_users_on_reset_password_token_solidus_auth_devise", unique: true
    t.index ["spree_api_key"], name: "index_spree_users_on_spree_api_key"
  end

  create_table "spree_variant_property_rule_conditions", id: :serial, force: :cascade do |t|
    t.integer "option_value_id"
    t.integer "variant_property_rule_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["variant_property_rule_id", "option_value_id"], name: "index_spree_variant_prop_rule_conditions_on_rule_and_optval"
  end

  create_table "spree_variant_property_rule_values", id: :serial, force: :cascade do |t|
    t.text "value"
    t.integer "position", default: 0
    t.integer "property_id"
    t.integer "variant_property_rule_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["property_id"], name: "index_spree_variant_property_rule_values_on_property_id"
    t.index ["variant_property_rule_id"], name: "index_spree_variant_property_rule_values_on_rule"
  end

  create_table "spree_variant_property_rules", id: :serial, force: :cascade do |t|
    t.integer "product_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "apply_to_all", default: true, null: false
    t.index ["product_id"], name: "index_spree_variant_property_rules_on_product_id"
  end

  create_table "spree_variants", id: :serial, force: :cascade do |t|
    t.string "sku", default: "", null: false
    t.decimal "weight", precision: 8, scale: 2, default: "0.0"
    t.decimal "height", precision: 8, scale: 2
    t.decimal "width", precision: 8, scale: 2
    t.decimal "depth", precision: 8, scale: 2
    t.datetime "deleted_at", precision: nil
    t.boolean "is_master", default: false
    t.integer "product_id"
    t.decimal "cost_price", precision: 10, scale: 2
    t.integer "position"
    t.string "cost_currency"
    t.boolean "track_inventory", default: true
    t.integer "tax_category_id"
    t.datetime "updated_at"
    t.datetime "created_at"
    t.bigint "shipping_category_id"
    t.string "gtin"
    t.string "condition"
    t.index ["position"], name: "index_spree_variants_on_position"
    t.index ["product_id"], name: "index_spree_variants_on_product_id"
    t.index ["shipping_category_id"], name: "index_spree_variants_on_shipping_category_id"
    t.index ["sku"], name: "index_spree_variants_on_sku"
    t.index ["tax_category_id"], name: "index_spree_variants_on_tax_category_id"
    t.index ["track_inventory"], name: "index_spree_variants_on_track_inventory"
  end

  create_table "spree_wallet_payment_sources", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "payment_source_type", null: false
    t.integer "payment_source_id", null: false
    t.boolean "default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "payment_source_id", "payment_source_type"], name: "index_spree_wallet_payment_sources_on_source_and_user", unique: true
    t.index ["user_id"], name: "index_spree_wallet_payment_sources_on_user_id"
  end

  create_table "spree_zone_members", id: :serial, force: :cascade do |t|
    t.string "zoneable_type"
    t.integer "zoneable_id"
    t.integer "zone_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["zone_id"], name: "index_spree_zone_members_on_zone_id"
    t.index ["zoneable_id", "zoneable_type"], name: "index_spree_zone_members_on_zoneable_id_and_zoneable_type"
  end

  create_table "spree_zones", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.integer "zone_members_count", default: 0
    t.datetime "created_at"
    t.datetime "updated_at"
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
    t.string "position"
    t.string "photo_url"
    t.jsonb "availability", default: {}, null: false
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
    t.index ["business_id"], name: "index_tenant_customers_on_business_id"
    t.index ["email", "business_id"], name: "index_tenant_customers_on_email_and_business_id", unique: true
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
  add_foreign_key "booking_policies", "businesses"
  add_foreign_key "booking_product_add_ons", "bookings"
  add_foreign_key "booking_product_add_ons", "product_variants"
  add_foreign_key "bookings", "businesses", on_delete: :cascade
  add_foreign_key "bookings", "promotions"
  add_foreign_key "bookings", "services"
  add_foreign_key "bookings", "staff_members"
  add_foreign_key "bookings", "tenant_customers"
  add_foreign_key "businesses", "service_templates"
  add_foreign_key "campaign_recipients", "marketing_campaigns"
  add_foreign_key "campaign_recipients", "tenant_customers"
  add_foreign_key "categories", "businesses"
  add_foreign_key "client_businesses", "businesses", on_delete: :cascade
  add_foreign_key "client_businesses", "users"
  add_foreign_key "invoices", "bookings"
  add_foreign_key "invoices", "businesses", on_delete: :cascade
  add_foreign_key "invoices", "promotions"
  add_foreign_key "invoices", "shipping_methods"
  add_foreign_key "invoices", "tax_rates"
  add_foreign_key "invoices", "tenant_customers"
  add_foreign_key "line_items", "product_variants"
  add_foreign_key "marketing_campaigns", "businesses", on_delete: :cascade
  add_foreign_key "marketing_campaigns", "promotions"
  add_foreign_key "orders", "businesses"
  add_foreign_key "orders", "shipping_methods"
  add_foreign_key "orders", "tax_rates"
  add_foreign_key "orders", "tenant_customers"
  add_foreign_key "page_sections", "pages"
  add_foreign_key "pages", "businesses", on_delete: :cascade
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "businesses"
  add_foreign_key "products", "categories"
  add_foreign_key "promotion_redemptions", "bookings"
  add_foreign_key "promotion_redemptions", "invoices"
  add_foreign_key "promotion_redemptions", "promotions"
  add_foreign_key "promotion_redemptions", "tenant_customers"
  add_foreign_key "promotions", "businesses", on_delete: :cascade
  add_foreign_key "services", "businesses", on_delete: :cascade
  add_foreign_key "services_staff_members", "services"
  add_foreign_key "services_staff_members", "staff_members"
  add_foreign_key "shipping_methods", "businesses"
  add_foreign_key "sms_messages", "bookings"
  add_foreign_key "sms_messages", "marketing_campaigns"
  add_foreign_key "sms_messages", "tenant_customers"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solidus_stripe_customers", "spree_payment_methods", column: "payment_method_id"
  add_foreign_key "solidus_stripe_payment_intents", "spree_orders", column: "order_id"
  add_foreign_key "solidus_stripe_payment_intents", "spree_payment_methods", column: "payment_method_id"
  add_foreign_key "solidus_stripe_slug_entries", "spree_payment_methods", column: "payment_method_id"
  add_foreign_key "spree_addresses", "businesses"
  add_foreign_key "spree_orders", "businesses"
  add_foreign_key "spree_orders_promotions", "spree_orders", column: "order_id", on_delete: :cascade, validate: false
  add_foreign_key "spree_payment_methods", "businesses"
  add_foreign_key "spree_products", "businesses"
  add_foreign_key "spree_products", "spree_taxons", column: "primary_taxon_id"
  add_foreign_key "spree_promotion_code_batches", "spree_promotions", column: "promotion_id"
  add_foreign_key "spree_promotion_codes", "spree_promotion_code_batches", column: "promotion_code_batch_id"
  add_foreign_key "spree_shipping_methods", "businesses"
  add_foreign_key "spree_stock_locations", "businesses"
  add_foreign_key "spree_stores", "businesses"
  add_foreign_key "spree_tax_rate_tax_categories", "spree_tax_categories", column: "tax_category_id"
  add_foreign_key "spree_tax_rate_tax_categories", "spree_tax_rates", column: "tax_rate_id"
  add_foreign_key "spree_taxonomies", "businesses"
  add_foreign_key "spree_wallet_payment_sources", "spree_users", column: "user_id"
  add_foreign_key "staff_assignments", "services"
  add_foreign_key "staff_assignments", "users"
  add_foreign_key "staff_members", "businesses", on_delete: :cascade
  add_foreign_key "staff_members", "users"
  add_foreign_key "tax_rates", "businesses"
  add_foreign_key "tenant_customers", "businesses", on_delete: :cascade
  add_foreign_key "users", "businesses", on_delete: :cascade
  add_foreign_key "users", "staff_members"
end
