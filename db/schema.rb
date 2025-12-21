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

ActiveRecord::Schema[8.1].define(version: 2025_12_21_174304) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gist"
  enable_extension "pg_catalog.plpgsql"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_admin_comments", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "namespace"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position"
    t.boolean "primary"
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "adp_payroll_export_configs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "round_total_hours", default: true, null: false
    t.integer "rounding_minutes", default: 15, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_adp_payroll_export_configs_on_active"
    t.index ["business_id"], name: "index_adp_payroll_export_configs_on_business_id", unique: true
  end

  create_table "adp_payroll_export_runs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "csv_data"
    t.jsonb "error_report", default: {}, null: false
    t.datetime "finished_at"
    t.jsonb "options", default: {}, null: false
    t.date "range_end", null: false
    t.date "range_start", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["business_id", "created_at"], name: "index_adp_payroll_export_runs_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_adp_payroll_export_runs_on_business_id"
    t.index ["status"], name: "index_adp_payroll_export_runs_on_status"
    t.index ["user_id"], name: "index_adp_payroll_export_runs_on_user_id"
  end

  create_table "auth_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_fingerprint"
    t.datetime "expires_at", null: false
    t.string "ip_address", null: false
    t.text "target_url", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.boolean "used", default: false, null: false
    t.text "user_agent", null: false
    t.integer "user_id", null: false
    t.index ["device_fingerprint"], name: "index_auth_tokens_on_device_fingerprint"
    t.index ["expires_at"], name: "index_auth_tokens_on_expires_at"
    t.index ["token"], name: "index_auth_tokens_on_token", unique: true
    t.index ["used", "expires_at"], name: "index_auth_tokens_on_used_and_expires_at"
    t.index ["user_id"], name: "index_auth_tokens_on_user_id"
  end

  create_table "authentication_bridges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "source_ip", limit: 45
    t.text "target_url", null: false
    t.string "token", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.string "user_agent", limit: 500
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_authentication_bridges_on_expires_at"
    t.index ["token"], name: "index_authentication_bridges_on_token", unique: true
    t.index ["user_id", "created_at"], name: "index_authentication_bridges_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_authentication_bridges_on_user_id"
  end

  create_table "blog_posts", force: :cascade do |t|
    t.string "author_email"
    t.string "author_name"
    t.string "category"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.text "excerpt", null: false
    t.string "featured_image_url"
    t.boolean "published", default: false
    t.datetime "published_at"
    t.date "release_date"
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_blog_posts_on_category"
    t.index ["published"], name: "index_blog_posts_on_published"
    t.index ["published_at"], name: "index_blog_posts_on_published_at"
    t.index ["slug"], name: "index_blog_posts_on_slug", unique: true
  end

  create_table "booking_policies", force: :cascade do |t|
    t.boolean "auto_confirm_bookings", default: false, null: false
    t.integer "buffer_time_mins"
    t.bigint "business_id", null: false
    t.integer "cancellation_window_mins"
    t.datetime "created_at", null: false
    t.jsonb "intake_fields"
    t.integer "interval_mins", default: 30
    t.integer "max_advance_days"
    t.integer "max_daily_bookings"
    t.integer "max_duration_mins"
    t.integer "min_advance_mins", default: 0
    t.integer "min_duration_mins"
    t.boolean "service_radius_enabled", default: false, null: false
    t.integer "service_radius_miles", default: 50, null: false
    t.datetime "updated_at", null: false
    t.boolean "use_fixed_intervals", default: false, null: false
    t.index ["business_id"], name: "index_booking_policies_on_business_id"
    t.index ["min_advance_mins"], name: "index_booking_policies_on_min_advance_mins"
    t.index ["use_fixed_intervals"], name: "index_booking_policies_on_use_fixed_intervals"
  end

  create_table "booking_product_add_ons", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.datetime "created_at", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.bigint "product_variant_id", null: false
    t.integer "quantity", default: 1, null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_booking_product_add_ons_on_booking_id"
    t.index ["product_variant_id"], name: "index_booking_product_add_ons_on_product_variant_id"
  end

  create_table "bookings", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.string "applied_promo_code"
    t.bigint "business_id"
    t.string "calendar_event_id"
    t.integer "calendar_event_status", default: 0
    t.text "cancellation_reason"
    t.integer "cancelled_by"
    t.datetime "created_at", null: false
    t.decimal "discount_amount", precision: 10, scale: 2
    t.datetime "end_time", null: false
    t.boolean "manager_override"
    t.text "notes"
    t.decimal "original_amount", precision: 10, scale: 2
    t.string "promo_code_type"
    t.decimal "promo_discount_amount", precision: 10, scale: 2
    t.bigint "promotion_id"
    t.boolean "review_request_suppressed", default: false, null: false
    t.bigint "service_id"
    t.bigint "service_variant_id"
    t.bigint "staff_member_id"
    t.datetime "start_time", null: false
    t.integer "status", default: 0
    t.bigint "tenant_customer_id"
    t.datetime "tip_reminder_sent_at"
    t.datetime "updated_at", null: false
    t.string "video_meeting_host_url"
    t.string "video_meeting_id"
    t.string "video_meeting_password"
    t.integer "video_meeting_provider", default: 0, null: false
    t.integer "video_meeting_status", default: 0, null: false
    t.string "video_meeting_url"
    t.index ["applied_promo_code"], name: "index_bookings_on_applied_promo_code"
    t.index ["business_id", "staff_member_id"], name: "index_bookings_on_business_and_staff_member"
    t.index ["business_id", "start_time"], name: "index_bookings_on_business_id_and_start_time"
    t.index ["business_id"], name: "index_bookings_on_business_id"
    t.index ["calendar_event_id"], name: "index_bookings_on_calendar_event_id"
    t.index ["calendar_event_status"], name: "index_bookings_on_calendar_event_status"
    t.index ["promo_code_type"], name: "index_bookings_on_promo_code_type"
    t.index ["promotion_id"], name: "index_bookings_on_promotion_id"
    t.index ["service_id"], name: "index_bookings_on_service_id"
    t.index ["service_variant_id"], name: "index_bookings_on_service_variant_id"
    t.index ["staff_member_id", "start_time", "end_time"], name: "index_bookings_on_staff_member_and_times"
    t.index ["staff_member_id", "start_time"], name: "index_bookings_on_staff_member_and_start_time"
    t.index ["staff_member_id", "status", "start_time", "end_time"], name: "index_bookings_on_staff_status_and_times"
    t.index ["staff_member_id", "status"], name: "index_bookings_on_staff_member_and_status"
    t.index ["staff_member_id"], name: "index_bookings_on_staff_member_id"
    t.index ["start_time", "end_time"], name: "index_bookings_on_start_time_and_end_time", using: :gist
    t.index ["start_time"], name: "index_bookings_on_start_time"
    t.index ["status"], name: "index_bookings_on_status"
    t.index ["tenant_customer_id", "start_time"], name: "index_bookings_on_tenant_customer_id_and_start_time"
    t.index ["tenant_customer_id"], name: "index_bookings_on_tenant_customer_id"
    t.index ["video_meeting_id"], name: "index_bookings_on_video_meeting_id"
    t.index ["video_meeting_status"], name: "index_bookings_on_video_meeting_status"
  end

  create_table "businesses", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "address"
    t.string "canonical_preference", default: "www", null: false, comment: "Preferred canonical version: \"www\" or \"apex\" for custom domains"
    t.string "city"
    t.integer "cname_check_attempts", default: 0, null: false
    t.boolean "cname_monitoring_active", default: false, null: false
    t.datetime "cname_setup_email_sent_at"
    t.datetime "created_at", null: false
    t.boolean "custom_domain_owned"
    t.text "description"
    t.datetime "domain_health_checked_at"
    t.boolean "domain_health_verified", default: false, null: false
    t.string "email"
    t.string "enhanced_accent_color", default: "red", null: false
    t.string "facebook_url"
    t.integer "gallery_columns", default: 3, null: false
    t.boolean "gallery_enabled", default: false, null: false
    t.integer "gallery_layout", default: 0, null: false
    t.text "google_business_address"
    t.boolean "google_business_manual", default: false
    t.string "google_business_name"
    t.string "google_business_phone"
    t.string "google_business_website"
    t.string "google_place_id"
    t.string "host_type"
    t.string "hostname"
    t.jsonb "hours"
    t.string "industry"
    t.string "instagram_url"
    t.string "linkedin_url"
    t.boolean "loyalty_program_enabled", default: false, null: false
    t.string "name", null: false
    t.boolean "payment_reminders_enabled", default: false, null: false
    t.string "phone"
    t.string "pinterest_url"
    t.decimal "points_per_dollar", precision: 8, scale: 2, default: "1.0", null: false
    t.decimal "points_per_product", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "points_per_service", precision: 8, scale: 2, default: "0.0", null: false
    t.boolean "referral_program_enabled", default: false, null: false
    t.boolean "render_domain_added", default: false, null: false
    t.integer "rental_buffer_mins", default: 30
    t.boolean "rental_deposit_preauth_enabled", default: false, null: false
    t.boolean "rental_late_fee_enabled", default: true
    t.decimal "rental_late_fee_percentage", precision: 5, scale: 2, default: "15.0"
    t.integer "rental_reminder_hours_before", default: 24
    t.boolean "rental_require_deposit_upfront", default: true
    t.bigint "service_template_id"
    t.boolean "show_estimate_page", default: true, null: false
    t.boolean "show_gallery_section", default: true, null: false
    t.boolean "show_products_section", default: true, null: false
    t.boolean "show_rentals_section", default: false
    t.boolean "show_services_section", default: true, null: false
    t.boolean "sms_auto_invitations_enabled", default: true, null: false
    t.boolean "sms_enabled", default: false, null: false
    t.boolean "sms_marketing_enabled", default: false, null: false
    t.string "state"
    t.string "status", default: "active", null: false
    t.boolean "stock_management_enabled", default: true, null: false
    t.string "stripe_account_id"
    t.datetime "stripe_connect_reminder_sent_at"
    t.string "stripe_customer_id"
    t.string "subdomain"
    t.boolean "subscription_discount_enabled", default: false, null: false
    t.text "subscription_discount_message"
    t.string "subscription_discount_type", default: "percentage"
    t.decimal "subscription_discount_value", precision: 10, scale: 2, default: "0.0"
    t.string "template_applied"
    t.string "tiktok_url"
    t.string "time_zone", default: "UTC"
    t.boolean "tip_mailer_if_no_tip_received", default: true, null: false
    t.string "twitter_url"
    t.datetime "updated_at", null: false
    t.boolean "video_autoplay_hero", default: true, null: false
    t.string "video_conversion_status"
    t.integer "video_display_location", default: 0, null: false
    t.string "video_title"
    t.string "website"
    t.string "website_layout", default: "basic", null: false
    t.string "youtube_url"
    t.string "zip"
    t.index ["canonical_preference"], name: "index_businesses_on_canonical_preference"
    t.index ["cname_monitoring_active"], name: "index_businesses_on_cname_monitoring_active"
    t.index ["description"], name: "index_businesses_on_description"
    t.index ["gallery_enabled"], name: "index_businesses_on_gallery_enabled"
    t.index ["google_business_manual"], name: "index_businesses_on_google_business_manual"
    t.index ["google_place_id"], name: "index_businesses_on_google_place_id", unique: true
    t.index ["host_type", "status", "domain_health_verified"], name: "index_businesses_on_custom_domain_health"
    t.index ["host_type"], name: "index_businesses_on_host_type"
    t.index ["hostname"], name: "index_businesses_on_hostname", unique: true
    t.index ["name"], name: "index_businesses_on_name"
    t.index ["rental_deposit_preauth_enabled"], name: "index_businesses_on_deposit_preauth_enabled", where: "(rental_deposit_preauth_enabled = true)"
    t.index ["service_template_id"], name: "index_businesses_on_service_template_id"
    t.index ["sms_auto_invitations_enabled"], name: "index_businesses_on_sms_auto_invitations_enabled"
    t.index ["status"], name: "index_businesses_on_status"
    t.index ["stock_management_enabled"], name: "index_businesses_on_stock_management_enabled"
    t.index ["stripe_account_id"], name: "index_businesses_on_stripe_account_id", unique: true
    t.index ["stripe_customer_id"], name: "index_businesses_on_stripe_customer_id", unique: true
    t.index ["subscription_discount_enabled"], name: "index_businesses_on_subscription_discount_enabled"
    t.index ["video_display_location"], name: "index_businesses_on_video_display_location"
    t.index ["website_layout"], name: "index_businesses_on_website_layout"
    t.check_constraint "subscription_discount_value >= 0::numeric", name: "businesses_subscription_discount_value_positive"
  end

  create_table "calendar_connections", force: :cascade do |t|
    t.text "access_token"
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.text "caldav_password"
    t.string "caldav_provider"
    t.string "caldav_url"
    t.string "caldav_username"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.integer "provider", null: false
    t.text "refresh_token"
    t.text "scopes"
    t.bigint "staff_member_id", null: false
    t.string "sync_token"
    t.datetime "token_expires_at"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_calendar_connections_on_active"
    t.index ["business_id", "staff_member_id", "provider"], name: "index_calendar_connections_on_business_staff_provider"
    t.index ["business_id"], name: "index_calendar_connections_on_business_id"
    t.index ["last_synced_at"], name: "index_calendar_connections_on_last_synced_at"
    t.index ["staff_member_id"], name: "index_calendar_connections_on_staff_member_id"
  end

  create_table "calendar_event_mappings", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "calendar_connection_id", null: false
    t.datetime "created_at", null: false
    t.string "external_calendar_id"
    t.string "external_event_id", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id", "calendar_connection_id"], name: "index_calendar_event_mappings_on_booking_connection"
    t.index ["booking_id"], name: "index_calendar_event_mappings_on_booking_id"
    t.index ["calendar_connection_id"], name: "index_calendar_event_mappings_on_calendar_connection_id"
    t.index ["external_event_id"], name: "index_calendar_event_mappings_on_external_event_id"
    t.index ["status"], name: "index_calendar_event_mappings_on_status"
  end

  create_table "calendar_sync_logs", force: :cascade do |t|
    t.integer "action", null: false
    t.bigint "calendar_event_mapping_id", null: false
    t.datetime "created_at", null: false
    t.text "message"
    t.jsonb "metadata", default: {}
    t.integer "outcome", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_calendar_sync_logs_on_action"
    t.index ["calendar_event_mapping_id"], name: "index_calendar_sync_logs_on_calendar_event_mapping_id"
    t.index ["created_at"], name: "index_calendar_sync_logs_on_created_at"
    t.index ["metadata"], name: "index_calendar_sync_logs_on_metadata", using: :gin
    t.index ["outcome"], name: "index_calendar_sync_logs_on_outcome"
  end

  create_table "campaign_recipients", force: :cascade do |t|
    t.boolean "clicked", default: false
    t.datetime "created_at", null: false
    t.bigint "marketing_campaign_id", null: false
    t.boolean "opened", default: false
    t.datetime "sent_at"
    t.integer "status", default: 0
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["marketing_campaign_id"], name: "index_campaign_recipients_on_marketing_campaign_id"
    t.index ["tenant_customer_id"], name: "index_campaign_recipients_on_tenant_customer_id"
  end

  create_table "client_businesses", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["business_id"], name: "index_client_businesses_on_business_id"
    t.index ["user_id", "business_id"], name: "index_client_businesses_on_user_id_and_business_id", unique: true
    t.index ["user_id"], name: "index_client_businesses_on_user_id"
  end

  create_table "client_document_events", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.bigint "business_id", null: false
    t.bigint "client_document_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}
    t.string "event_type", null: false
    t.string "ip_address"
    t.text "message"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["business_id"], name: "index_client_document_events_on_business_id"
    t.index ["client_document_id", "event_type"], name: "idx_on_client_document_id_event_type_808a7c3557"
    t.index ["client_document_id"], name: "index_client_document_events_on_client_document_id"
  end

  create_table "client_documents", force: :cascade do |t|
    t.text "body"
    t.bigint "business_id", null: false
    t.string "checkout_session_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.decimal "deposit_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "deposit_paid_at"
    t.bigint "document_template_id"
    t.string "document_type", null: false
    t.bigint "documentable_id"
    t.string "documentable_type"
    t.bigint "invoice_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "payment_intent_id"
    t.boolean "payment_required", default: false, null: false
    t.datetime "sent_at"
    t.boolean "signature_required", default: true, null: false
    t.datetime "signed_at"
    t.string "status", default: "draft", null: false
    t.bigint "tenant_customer_id"
    t.string "title"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "status"], name: "index_client_documents_on_business_id_and_status"
    t.index ["business_id"], name: "index_client_documents_on_business_id"
    t.index ["checkout_session_id"], name: "index_client_documents_on_checkout_session_id"
    t.index ["document_template_id"], name: "index_client_documents_on_document_template_id"
    t.index ["document_type", "status"], name: "index_client_documents_on_document_type_and_status"
    t.index ["documentable_type", "documentable_id"], name: "index_client_documents_on_documentable"
    t.index ["invoice_id"], name: "index_client_documents_on_invoice_id"
    t.index ["payment_intent_id"], name: "index_client_documents_on_payment_intent_id"
    t.index ["tenant_customer_id"], name: "index_client_documents_on_tenant_customer_id"
    t.index ["token"], name: "index_client_documents_on_token", unique: true
  end

  create_table "csv_import_runs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.integer "created_count", default: 0
    t.integer "error_count", default: 0
    t.jsonb "error_report", default: {}, null: false
    t.datetime "finished_at"
    t.string "import_type", null: false
    t.string "original_filename"
    t.integer "processed_rows", default: 0
    t.integer "skipped_count", default: 0
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.integer "total_rows", default: 0
    t.datetime "updated_at", null: false
    t.integer "updated_count", default: 0
    t.bigint "user_id"
    t.index ["business_id", "created_at"], name: "index_csv_import_runs_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_csv_import_runs_on_business_id"
    t.index ["import_type"], name: "index_csv_import_runs_on_import_type"
    t.index ["status"], name: "index_csv_import_runs_on_status"
    t.index ["user_id"], name: "index_csv_import_runs_on_user_id"
  end

  create_table "customer_subscriptions", force: :cascade do |t|
    t.boolean "allow_customer_preferences", default: true, null: false
    t.integer "billing_day_of_month", null: false
    t.bigint "business_id", null: false
    t.text "cancellation_reason"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "customer_out_of_stock_preference"
    t.json "customer_preferences"
    t.string "customer_rebooking_option", default: "business_default"
    t.string "customer_rebooking_preference"
    t.text "failure_reason"
    t.string "frequency", default: "monthly", null: false
    t.date "last_processed_date"
    t.date "next_billing_date", null: false
    t.text "notes"
    t.integer "out_of_stock_action", default: 0
    t.bigint "preferred_staff_member_id"
    t.time "preferred_time_slot"
    t.bigint "product_id"
    t.bigint "product_variant_id"
    t.integer "quantity", default: 1, null: false
    t.bigint "service_id"
    t.integer "service_rebooking_preference"
    t.integer "status", default: 0, null: false
    t.string "stripe_subscription_id"
    t.decimal "subscription_price", precision: 10, scale: 2, null: false
    t.string "subscription_type", null: false
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "status"], name: "index_customer_subscriptions_on_business_id_and_status"
    t.index ["business_id"], name: "index_customer_subscriptions_on_business_id"
    t.index ["customer_out_of_stock_preference"], name: "idx_on_customer_out_of_stock_preference_0a07f79334"
    t.index ["customer_rebooking_option"], name: "index_customer_subscriptions_on_customer_rebooking_option"
    t.index ["customer_rebooking_preference"], name: "index_customer_subscriptions_on_customer_rebooking_preference"
    t.index ["frequency"], name: "index_customer_subscriptions_on_frequency"
    t.index ["next_billing_date", "status"], name: "index_customer_subscriptions_on_next_billing_date_and_status"
    t.index ["preferred_staff_member_id"], name: "index_customer_subscriptions_on_preferred_staff_member_id"
    t.index ["product_id"], name: "index_customer_subscriptions_on_product_id"
    t.index ["product_variant_id"], name: "index_customer_subscriptions_on_product_variant_id"
    t.index ["service_id"], name: "index_customer_subscriptions_on_service_id"
    t.index ["stripe_subscription_id"], name: "index_customer_subscriptions_on_stripe_subscription_id", unique: true
    t.index ["subscription_type", "status"], name: "index_customer_subscriptions_on_subscription_type_and_status"
    t.index ["tenant_customer_id", "status"], name: "index_customer_subscriptions_on_tenant_customer_id_and_status"
    t.index ["tenant_customer_id"], name: "index_customer_subscriptions_on_tenant_customer_id"
    t.check_constraint "product_id IS NOT NULL AND service_id IS NULL OR product_id IS NULL AND service_id IS NOT NULL", name: "customer_subscriptions_product_or_service_check"
  end

  create_table "discount_codes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "discount_type", null: false
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.datetime "expires_at"
    t.bigint "generated_by_referral_id"
    t.integer "max_usage", default: 1
    t.integer "points_redeemed", default: 0, null: false
    t.boolean "single_use", default: true, null: false
    t.string "stripe_coupon_id"
    t.bigint "tenant_customer_id"
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.bigint "used_by_customer_id"
    t.index ["active"], name: "index_discount_codes_on_active"
    t.index ["business_id"], name: "index_discount_codes_on_business_id"
    t.index ["code"], name: "index_discount_codes_on_code"
    t.index ["expires_at"], name: "index_discount_codes_on_expires_at"
    t.index ["generated_by_referral_id"], name: "index_discount_codes_on_generated_by_referral_id"
    t.index ["points_redeemed"], name: "index_discount_codes_on_points_redeemed"
    t.index ["stripe_coupon_id"], name: "index_discount_codes_on_stripe_coupon_id"
    t.index ["tenant_customer_id"], name: "index_discount_codes_on_tenant_customer_id"
    t.index ["used_by_customer_id"], name: "index_discount_codes_on_used_by_customer_id"
  end

  create_table "document_signatures", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "client_document_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.integer "position"
    t.string "role", default: "client", null: false
    t.text "signature_data"
    t.datetime "signed_at"
    t.string "signer_email"
    t.string "signer_name", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["business_id"], name: "index_document_signatures_on_business_id"
    t.index ["client_document_id", "role"], name: "index_document_signatures_on_client_document_id_and_role"
    t.index ["client_document_id"], name: "index_document_signatures_on_client_document_id"
  end

  create_table "document_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "body", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.string "document_type", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["business_id", "document_type", "active"], name: "idx_on_business_id_document_type_active_ad65b373a5"
    t.index ["business_id"], name: "index_document_templates_on_business_id"
  end

  create_table "email_marketing_connections", force: :cascade do |t|
    t.text "access_token"
    t.string "account_email"
    t.string "account_id"
    t.boolean "active", default: true
    t.string "api_server"
    t.bigint "business_id", null: false
    t.jsonb "config", default: {}
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.string "default_list_id"
    t.string "default_list_name"
    t.jsonb "field_mappings", default: {}
    t.datetime "last_synced_at"
    t.integer "provider", default: 0, null: false
    t.boolean "receive_unsubscribe_webhooks", default: true
    t.text "refresh_token"
    t.boolean "sync_on_customer_create", default: true
    t.boolean "sync_on_customer_update", default: true
    t.integer "sync_strategy", default: 0, null: false
    t.datetime "token_expires_at"
    t.integer "total_contacts_synced", default: 0
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_email_marketing_connections_on_active"
    t.index ["business_id", "provider"], name: "idx_email_marketing_conn_business_provider", unique: true
    t.index ["business_id"], name: "index_email_marketing_connections_on_business_id"
    t.index ["provider"], name: "index_email_marketing_connections_on_provider"
  end

  create_table "email_marketing_sync_logs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "completed_at"
    t.integer "contacts_created", default: 0
    t.integer "contacts_failed", default: 0
    t.integer "contacts_synced", default: 0
    t.integer "contacts_updated", default: 0
    t.datetime "created_at", null: false
    t.integer "direction", default: 0, null: false
    t.bigint "email_marketing_connection_id", null: false
    t.jsonb "error_details", default: []
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.jsonb "summary", default: {}
    t.integer "sync_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_email_marketing_sync_logs_on_business_id"
    t.index ["created_at"], name: "index_email_marketing_sync_logs_on_created_at"
    t.index ["email_marketing_connection_id"], name: "idx_on_email_marketing_connection_id_8d816d900b"
    t.index ["status"], name: "index_email_marketing_sync_logs_on_status"
    t.index ["sync_type"], name: "index_email_marketing_sync_logs_on_sync_type"
  end

  create_table "estimate_items", force: :cascade do |t|
    t.decimal "cost_rate", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.boolean "customer_declined", default: false, null: false
    t.boolean "customer_selected", default: true, null: false
    t.string "description"
    t.bigint "estimate_id", null: false
    t.decimal "hourly_rate", precision: 10, scale: 2
    t.decimal "hours", precision: 10, scale: 2
    t.integer "item_type", default: 0, null: false
    t.boolean "optional", default: false, null: false
    t.integer "position", default: 0, null: false
    t.bigint "product_id"
    t.bigint "product_variant_id"
    t.integer "qty"
    t.bigint "service_id"
    t.decimal "tax_rate", precision: 10, scale: 2
    t.decimal "total", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["estimate_id", "optional"], name: "index_estimate_items_on_estimate_id_and_optional"
    t.index ["estimate_id", "position"], name: "index_estimate_items_on_estimate_id_and_position"
    t.index ["estimate_id"], name: "index_estimate_items_on_estimate_id"
    t.index ["item_type"], name: "index_estimate_items_on_item_type"
    t.index ["product_id"], name: "index_estimate_items_on_product_id"
    t.index ["product_variant_id"], name: "index_estimate_items_on_product_variant_id"
    t.index ["service_id"], name: "index_estimate_items_on_service_id"
  end

  create_table "estimate_messages", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.bigint "estimate_id", null: false
    t.text "message", null: false
    t.string "sender_email"
    t.string "sender_name"
    t.string "sender_type", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_estimate_messages_on_business_id"
    t.index ["estimate_id", "created_at"], name: "index_estimate_messages_on_estimate_id_and_created_at"
    t.index ["estimate_id"], name: "index_estimate_messages_on_estimate_id"
  end

  create_table "estimate_versions", force: :cascade do |t|
    t.text "change_notes"
    t.datetime "created_at", null: false
    t.bigint "estimate_id", null: false
    t.jsonb "snapshot", null: false
    t.integer "version_number", null: false
    t.index ["estimate_id", "version_number"], name: "index_estimate_versions_on_estimate_id_and_version_number", unique: true
    t.index ["estimate_id"], name: "index_estimate_versions_on_estimate_id"
  end

  create_table "estimates", force: :cascade do |t|
    t.string "address"
    t.datetime "approved_at"
    t.bigint "booking_id"
    t.bigint "business_id", null: false
    t.string "checkout_session_id"
    t.string "city"
    t.datetime "created_at", null: false
    t.integer "current_version", default: 1, null: false
    t.text "customer_notes"
    t.datetime "declined_at"
    t.datetime "deposit_paid_at"
    t.string "email"
    t.string "estimate_number"
    t.string "first_name"
    t.boolean "has_optional_items", default: false, null: false
    t.text "internal_notes"
    t.string "last_name"
    t.decimal "optional_items_subtotal", precision: 10, scale: 2, default: "0.0"
    t.decimal "optional_items_taxes", precision: 10, scale: 2, default: "0.0"
    t.string "payment_intent_id"
    t.datetime "pdf_generated_at"
    t.string "phone"
    t.datetime "proposed_end_time"
    t.datetime "proposed_start_time"
    t.decimal "required_deposit", precision: 10, scale: 2
    t.datetime "sent_at"
    t.text "signature_data"
    t.string "signature_name"
    t.datetime "signed_at"
    t.string "state"
    t.integer "status"
    t.decimal "subtotal", precision: 10, scale: 2
    t.decimal "taxes", precision: 10, scale: 2
    t.bigint "tenant_customer_id"
    t.string "token", null: false
    t.decimal "total", precision: 10, scale: 2
    t.integer "total_versions", default: 1, null: false
    t.datetime "updated_at", null: false
    t.integer "valid_for_days", default: 30, null: false
    t.datetime "viewed_at"
    t.string "zip"
    t.index ["booking_id"], name: "index_estimates_on_booking_id"
    t.index ["business_id", "estimate_number"], name: "index_estimates_on_business_id_and_estimate_number", unique: true
    t.index ["business_id"], name: "index_estimates_on_business_id"
    t.index ["checkout_session_id"], name: "index_estimates_on_checkout_session_id"
    t.index ["has_optional_items"], name: "index_estimates_on_has_optional_items"
    t.index ["payment_intent_id"], name: "index_estimates_on_payment_intent_id"
    t.index ["status"], name: "index_estimates_on_status"
    t.index ["tenant_customer_id"], name: "index_estimates_on_tenant_customer_id"
  end

  create_table "external_calendar_events", force: :cascade do |t|
    t.bigint "calendar_connection_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.string "external_calendar_id"
    t.string "external_event_id", null: false
    t.datetime "last_imported_at"
    t.datetime "starts_at", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["calendar_connection_id", "external_event_id"], name: "index_external_calendar_events_on_connection_event_id", unique: true
    t.index ["calendar_connection_id"], name: "index_external_calendar_events_on_calendar_connection_id"
    t.index ["external_event_id"], name: "index_external_calendar_events_on_external_event_id"
    t.index ["last_imported_at"], name: "index_external_calendar_events_on_last_imported_at"
    t.index ["starts_at", "ends_at"], name: "index_external_calendar_events_on_starts_at_and_ends_at"
  end

  create_table "friendly_id_slugs", id: :serial, force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.datetime "updated_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_id"
    t.index ["sluggable_type"], name: "index_friendly_id_slugs_on_sluggable_type"
  end

  create_table "gallery_photos", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "photo_source", default: 0, null: false
    t.integer "position", null: false
    t.integer "source_attachment_id"
    t.integer "source_id"
    t.string "source_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["business_id", "position"], name: "index_gallery_photos_on_business_id_and_position", unique: true
    t.index ["business_id"], name: "index_gallery_photos_on_business_id"
    t.index ["source_type", "source_id"], name: "index_gallery_photos_on_source_type_and_source_id", where: "(source_type IS NOT NULL)"
  end

  create_table "integration_credentials", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.jsonb "config"
    t.datetime "created_at", null: false
    t.integer "provider"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_integration_credentials_on_business_id"
  end

  create_table "integrations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.jsonb "config"
    t.datetime "created_at", null: false
    t.integer "kind", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_integrations_on_business_id"
  end

  create_table "invalidated_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "invalidated_at", null: false
    t.string "session_token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_invalidated_sessions_on_expires_at"
    t.index ["session_token", "expires_at"], name: "index_invalidated_sessions_on_token_and_expires_at"
    t.index ["session_token"], name: "index_invalidated_sessions_on_session_token", unique: true
    t.index ["user_id", "session_token"], name: "index_invalidated_sessions_on_user_id_and_session_token"
    t.index ["user_id"], name: "index_invalidated_sessions_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.bigint "booking_id"
    t.bigint "business_id"
    t.datetime "created_at", null: false
    t.decimal "discount_amount", precision: 10, scale: 2
    t.datetime "due_date"
    t.string "guest_access_token"
    t.string "invoice_number", null: false
    t.bigint "order_id"
    t.decimal "original_amount", precision: 10, scale: 2
    t.bigint "promotion_id"
    t.integer "quickbooks_export_status", default: 0, null: false
    t.datetime "quickbooks_exported_at"
    t.string "quickbooks_invoice_id"
    t.boolean "review_request_suppressed", default: false, null: false
    t.bigint "shipping_method_id"
    t.integer "status", default: 0
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "tax_rate_id"
    t.bigint "tenant_customer_id", null: false
    t.decimal "tip_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "tip_amount_received_initially", precision: 10, scale: 2, default: "0.0"
    t.boolean "tip_received_on_initial_payment", default: false, null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_invoices_on_booking_id"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number"
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["promotion_id"], name: "index_invoices_on_promotion_id"
    t.index ["quickbooks_invoice_id"], name: "index_invoices_on_quickbooks_invoice_id"
    t.index ["shipping_method_id"], name: "index_invoices_on_shipping_method_id"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["tax_rate_id"], name: "index_invoices_on_tax_rate_id"
    t.index ["tenant_customer_id"], name: "index_invoices_on_tenant_customer_id"
    t.index ["tip_amount"], name: "index_invoices_on_tip_amount"
  end

  create_table "job_attachments", force: :cascade do |t|
    t.bigint "attachable_id", null: false
    t.string "attachable_type", null: false
    t.integer "attachment_type", default: 0, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "instructions"
    t.integer "position", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_user_id"
    t.integer "visibility", default: 0, null: false
    t.index ["attachable_type", "attachable_id"], name: "index_job_attachments_on_attachable_type_and_attachable_id"
    t.index ["business_id", "attachment_type"], name: "index_job_attachments_on_business_id_and_attachment_type"
    t.index ["business_id"], name: "index_job_attachments_on_business_id"
    t.index ["uploaded_by_user_id"], name: "index_job_attachments_on_uploaded_by_user_id"
  end

  create_table "job_form_submissions", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_user_id"
    t.bigint "booking_id", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_form_template_id", null: false
    t.text "notes"
    t.jsonb "responses", default: {}, null: false
    t.bigint "staff_member_id"
    t.integer "status", default: 0, null: false
    t.datetime "submitted_at"
    t.bigint "submitted_by_user_id"
    t.datetime "updated_at", null: false
    t.index ["approved_by_user_id"], name: "index_job_form_submissions_on_approved_by_user_id"
    t.index ["booking_id", "job_form_template_id"], name: "idx_job_form_submissions_booking_template"
    t.index ["booking_id"], name: "index_job_form_submissions_on_booking_id"
    t.index ["business_id", "status"], name: "index_job_form_submissions_on_business_and_status"
    t.index ["business_id", "status"], name: "index_job_form_submissions_on_business_id_and_status"
    t.index ["business_id"], name: "index_job_form_submissions_on_business_id"
    t.index ["job_form_template_id"], name: "index_job_form_submissions_on_job_form_template_id"
    t.index ["staff_member_id"], name: "index_job_form_submissions_on_staff_member_id"
    t.index ["submitted_by_user_id"], name: "index_job_form_submissions_on_submitted_by_user_id"
  end

  create_table "job_form_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "fields", default: {"fields" => []}, null: false
    t.integer "form_type", default: 0, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "active"], name: "index_job_form_templates_on_business_id_and_active"
    t.index ["business_id", "form_type"], name: "index_job_form_templates_on_business_id_and_form_type"
    t.index ["business_id"], name: "index_job_form_templates_on_business_id"
  end

  create_table "line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "lineable_id", null: false
    t.string "lineable_type", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.bigint "product_variant_id"
    t.integer "quantity", null: false
    t.bigint "service_id"
    t.bigint "staff_member_id"
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["lineable_type", "lineable_id"], name: "index_line_items_on_lineable"
    t.index ["product_variant_id"], name: "index_line_items_on_product_variant_id"
    t.index ["service_id"], name: "index_line_items_on_service_id"
    t.index ["staff_member_id"], name: "index_line_items_on_staff_member_id"
  end

  create_table "locations", force: :cascade do |t|
    t.string "address"
    t.bigint "business_id", null: false
    t.string "city"
    t.datetime "created_at", null: false
    t.jsonb "hours"
    t.string "name"
    t.string "state"
    t.datetime "updated_at", null: false
    t.string "zip"
    t.index ["business_id"], name: "index_locations_on_business_id"
  end

  create_table "loyalty_programs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "points_for_booking", default: 0, null: false
    t.integer "points_for_referral", default: 0, null: false
    t.string "points_name", default: "points", null: false
    t.decimal "points_per_dollar", precision: 8, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_loyalty_programs_on_active"
    t.index ["business_id"], name: "index_loyalty_programs_on_business_id"
  end

  create_table "loyalty_redemptions", force: :cascade do |t|
    t.bigint "booking_id"
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.decimal "discount_amount_applied", precision: 10, scale: 2
    t.string "discount_code", null: false
    t.bigint "loyalty_reward_id", null: false
    t.bigint "order_id"
    t.integer "points_redeemed", null: false
    t.string "status", default: "active", null: false
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_loyalty_redemptions_on_booking_id"
    t.index ["business_id"], name: "index_loyalty_redemptions_on_business_id"
    t.index ["created_at"], name: "index_loyalty_redemptions_on_created_at"
    t.index ["discount_code"], name: "index_loyalty_redemptions_on_discount_code", unique: true
    t.index ["loyalty_reward_id"], name: "index_loyalty_redemptions_on_loyalty_reward_id"
    t.index ["order_id"], name: "index_loyalty_redemptions_on_order_id"
    t.index ["status"], name: "index_loyalty_redemptions_on_status"
    t.index ["tenant_customer_id"], name: "index_loyalty_redemptions_on_tenant_customer_id"
  end

  create_table "loyalty_rewards", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.bigint "loyalty_program_id", null: false
    t.string "name", null: false
    t.integer "points_required", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_loyalty_rewards_on_active"
    t.index ["business_id"], name: "index_loyalty_rewards_on_business_id"
    t.index ["loyalty_program_id"], name: "index_loyalty_rewards_on_loyalty_program_id"
    t.index ["points_required"], name: "index_loyalty_rewards_on_points_required"
  end

  create_table "loyalty_transactions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "expires_at"
    t.integer "points_amount", null: false
    t.bigint "related_booking_id"
    t.bigint "related_order_id"
    t.bigint "related_referral_id"
    t.bigint "tenant_customer_id", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_loyalty_transactions_on_business_id"
    t.index ["created_at"], name: "index_loyalty_transactions_on_created_at"
    t.index ["expires_at"], name: "index_loyalty_transactions_on_expires_at"
    t.index ["related_booking_id"], name: "index_loyalty_transactions_on_related_booking_id"
    t.index ["related_order_id"], name: "index_loyalty_transactions_on_related_order_id"
    t.index ["related_referral_id"], name: "index_loyalty_transactions_on_related_referral_id"
    t.index ["tenant_customer_id", "transaction_type"], name: "idx_on_tenant_customer_id_transaction_type_ddac95c67b"
    t.index ["tenant_customer_id"], name: "index_loyalty_transactions_on_tenant_customer_id"
    t.index ["transaction_type"], name: "index_loyalty_transactions_on_transaction_type"
  end

  create_table "marketing_campaigns", force: :cascade do |t|
    t.boolean "active", default: true
    t.bigint "business_id", null: false
    t.integer "campaign_type", default: 0
    t.datetime "completed_at"
    t.text "content"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_date"
    t.string "name", null: false
    t.bigint "promotion_id"
    t.datetime "scheduled_at"
    t.jsonb "settings"
    t.datetime "start_date"
    t.datetime "started_at"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_marketing_campaigns_on_business_id"
    t.index ["name", "business_id"], name: "index_marketing_campaigns_on_name_and_business_id", unique: true
    t.index ["promotion_id"], name: "index_marketing_campaigns_on_promotion_id"
  end

  create_table "migration_metadata_20250822201249", primary_key: "key", id: { type: :string, limit: 50 }, force: :cascade do |t|
    t.text "value"
  end

  create_table "notification_templates", force: :cascade do |t|
    t.text "body"
    t.bigint "business_id", null: false
    t.integer "channel"
    t.datetime "created_at", null: false
    t.string "event_type"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_notification_templates_on_business_id"
  end

  create_table "oauth_flash_messages", force: :cascade do |t|
    t.string "alert"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "notice"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.boolean "used", default: false, null: false
    t.index ["expires_at"], name: "index_oauth_flash_messages_on_expires_at"
    t.index ["token"], name: "index_oauth_flash_messages_on_token", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.string "applied_promo_code"
    t.text "billing_address"
    t.bigint "booking_id"
    t.bigint "business_id"
    t.datetime "created_at", null: false
    t.bigint "customer_subscription_id"
    t.text "notes"
    t.string "order_number", null: false
    t.integer "order_type", default: 0
    t.string "promo_code_type"
    t.decimal "promo_discount_amount", precision: 10, scale: 2
    t.boolean "review_request_suppressed", default: false, null: false
    t.text "shipping_address"
    t.decimal "shipping_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "shipping_method_id"
    t.string "status", default: "pending_payment", null: false
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "tax_rate_id"
    t.bigint "tenant_customer_id"
    t.decimal "tip_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "tip_amount_received_initially", precision: 10, scale: 2, default: "0.0"
    t.boolean "tip_received_on_initial_payment", default: false, null: false
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["applied_promo_code"], name: "index_orders_on_applied_promo_code"
    t.index ["booking_id"], name: "index_orders_on_booking_id"
    t.index ["business_id", "created_at"], name: "index_orders_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_orders_on_business_id"
    t.index ["customer_subscription_id"], name: "index_orders_on_customer_subscription_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["promo_code_type"], name: "index_orders_on_promo_code_type"
    t.index ["shipping_method_id"], name: "index_orders_on_shipping_method_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["tax_rate_id"], name: "index_orders_on_tax_rate_id"
    t.index ["tenant_customer_id", "created_at"], name: "index_orders_on_tenant_customer_id_and_created_at"
    t.index ["tenant_customer_id"], name: "index_orders_on_tenant_customer_id"
    t.index ["tip_amount"], name: "index_orders_on_tip_amount"
    t.check_constraint "status::text = ANY (ARRAY['pending_payment'::character varying, 'paid'::character varying, 'cancelled'::character varying, 'shipped'::character varying, 'refunded'::character varying, 'processing'::character varying, 'completed'::character varying, 'business_deleted'::character varying]::text[])", name: "status_enum_check"
  end

  create_table "page_sections", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "animation_type"
    t.json "background_settings", default: {}
    t.json "content"
    t.datetime "created_at", null: false
    t.string "custom_css_classes"
    t.bigint "page_id", null: false
    t.integer "position"
    t.json "section_config", default: {}
    t.integer "section_type", default: 0
    t.datetime "updated_at", null: false
    t.index ["animation_type"], name: "index_page_sections_on_animation_type"
    t.index ["page_id"], name: "index_page_sections_on_page_id"
  end

  create_table "page_versions", force: :cascade do |t|
    t.text "change_notes"
    t.json "content_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "page_id", null: false
    t.datetime "published_at", precision: nil
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["created_by_id"], name: "index_page_versions_on_created_by_id"
    t.index ["page_id", "version_number"], name: "index_page_versions_on_page_id_and_version_number", unique: true
    t.index ["page_id"], name: "index_page_versions_on_page_id"
    t.index ["published_at"], name: "index_page_versions_on_published_at"
    t.index ["status"], name: "index_page_versions_on_status"
  end

  create_table "pages", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.json "custom_theme_settings", default: {}
    t.datetime "last_viewed_at"
    t.integer "menu_order"
    t.string "meta_description"
    t.integer "page_type"
    t.decimal "performance_score", precision: 5, scale: 2
    t.integer "priority", default: 0, null: false
    t.boolean "published"
    t.datetime "published_at"
    t.text "seo_keywords"
    t.string "seo_title"
    t.boolean "show_in_menu"
    t.string "slug"
    t.integer "status", default: 1, null: false
    t.string "template_applied"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0, null: false
    t.index ["business_id"], name: "index_pages_on_business_id"
    t.index ["last_viewed_at"], name: "index_pages_on_last_viewed_at"
    t.index ["priority"], name: "index_pages_on_priority"
    t.index ["status"], name: "index_pages_on_status"
    t.index ["template_applied"], name: "index_pages_on_template_applied"
    t.index ["view_count"], name: "index_pages_on_view_count"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.decimal "business_amount", precision: 10, scale: 2, null: false
    t.bigint "business_id"
    t.datetime "created_at", null: false
    t.text "failure_reason"
    t.bigint "invoice_id"
    t.bigint "order_id"
    t.datetime "paid_at"
    t.string "payment_method", default: "card"
    t.decimal "platform_fee_amount", precision: 10, scale: 2, null: false
    t.string "quickbooks_payment_id"
    t.text "refund_reason"
    t.decimal "refunded_amount", precision: 10, scale: 2, default: "0.0"
    t.integer "status", default: 0
    t.string "stripe_charge_id"
    t.string "stripe_customer_id"
    t.decimal "stripe_fee_amount", precision: 10, scale: 2, null: false
    t.string "stripe_payment_intent_id"
    t.string "stripe_transfer_id"
    t.bigint "tenant_customer_id"
    t.decimal "tip_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "tip_amount_received_initially", precision: 10, scale: 2, default: "0.0"
    t.boolean "tip_received_on_initial_payment", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "paid_at"], name: "index_payments_on_business_id_and_paid_at"
    t.index ["business_id", "status"], name: "index_payments_on_business_id_and_status"
    t.index ["business_id"], name: "index_payments_on_business_id"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["quickbooks_payment_id"], name: "index_payments_on_quickbooks_payment_id"
    t.index ["stripe_charge_id"], name: "index_payments_on_stripe_charge_id"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
    t.index ["tenant_customer_id"], name: "index_payments_on_tenant_customer_id"
    t.index ["tip_amount"], name: "index_payments_on_tip_amount"
  end

  create_table "pending_sms_notifications", force: :cascade do |t|
    t.bigint "booking_id"
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.string "deduplication_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "failed_at"
    t.text "failure_reason"
    t.bigint "invoice_id"
    t.string "notification_type", null: false
    t.bigint "order_id"
    t.text "phone_number", null: false
    t.datetime "processed_at"
    t.datetime "queued_at", null: false
    t.string "sms_type", null: false
    t.string "status", default: "pending"
    t.json "template_data", null: false
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_pending_sms_notifications_on_booking_id"
    t.index ["business_id", "tenant_customer_id"], name: "idx_on_business_id_tenant_customer_id_7f0c30b769"
    t.index ["business_id"], name: "index_pending_sms_notifications_on_business_id"
    t.index ["deduplication_key"], name: "index_pending_sms_notifications_on_deduplication_key", unique: true
    t.index ["expires_at"], name: "index_pending_sms_notifications_on_expires_at"
    t.index ["invoice_id"], name: "index_pending_sms_notifications_on_invoice_id"
    t.index ["notification_type"], name: "index_pending_sms_notifications_on_notification_type"
    t.index ["order_id"], name: "index_pending_sms_notifications_on_order_id"
    t.index ["phone_number"], name: "index_pending_sms_notifications_on_phone_number"
    t.index ["status", "queued_at"], name: "index_pending_sms_notifications_on_status_and_queued_at"
    t.index ["tenant_customer_id"], name: "index_pending_sms_notifications_on_tenant_customer_id"
  end

  create_table "policy_acceptances", force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "policy_type", null: false
    t.string "policy_version", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["accepted_at"], name: "index_policy_acceptances_on_accepted_at"
    t.index ["policy_version"], name: "index_policy_acceptances_on_policy_version"
    t.index ["user_id", "policy_type"], name: "index_policy_acceptances_on_user_and_type"
    t.index ["user_id"], name: "index_policy_acceptances_on_user_id"
  end

  create_table "policy_versions", force: :cascade do |t|
    t.boolean "active", default: false
    t.text "change_summary"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "effective_date"
    t.string "policy_type", null: false
    t.boolean "requires_notification", default: false
    t.string "termly_embed_id"
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["effective_date"], name: "index_policy_versions_on_effective_date"
    t.index ["policy_type", "active"], name: "index_policy_versions_on_policy_type_and_active"
    t.index ["policy_type", "version"], name: "index_policy_versions_on_policy_type_and_version", unique: true
  end

  create_table "product_service_add_ons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id"
    t.bigint "service_id"
    t.datetime "updated_at", null: false
  end

  create_table "product_variants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "options"
    t.decimal "price_modifier", precision: 10, scale: 2
    t.bigint "product_id", null: false
    t.string "quickbooks_item_id"
    t.integer "reserved_quantity"
    t.string "sku"
    t.integer "stock_quantity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
    t.index ["quickbooks_item_id"], name: "index_product_variants_on_quickbooks_item_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "allow_customer_preferences", default: true, null: false
    t.boolean "allow_daily_rental", default: true
    t.boolean "allow_discounts", default: true, null: false
    t.boolean "allow_hourly_rental", default: true
    t.boolean "allow_weekly_rental", default: true
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "document_template_id"
    t.boolean "featured", default: false
    t.boolean "hide_when_out_of_stock", default: false, null: false
    t.decimal "hourly_rate", precision: 10, scale: 2
    t.bigint "location_id"
    t.integer "max_rental_duration_mins"
    t.integer "min_rental_duration_mins", default: 60
    t.string "name", null: false
    t.integer "position", default: 0
    t.decimal "price", precision: 10, scale: 2, null: false
    t.integer "product_type", null: false
    t.jsonb "rental_availability_schedule", default: {}, null: false
    t.integer "rental_buffer_mins", default: 0
    t.string "rental_category", default: "equipment"
    t.jsonb "rental_duration_options", default: [], null: false
    t.integer "rental_quantity_available", default: 1
    t.decimal "security_deposit", precision: 10, scale: 2, default: "0.0"
    t.boolean "show_stock_to_customers", default: true, null: false
    t.integer "stock_quantity", default: 0, null: false
    t.string "subscription_billing_cycle", default: "monthly"
    t.decimal "subscription_discount_percentage", precision: 5, scale: 2
    t.boolean "subscription_enabled", default: false, null: false
    t.string "subscription_out_of_stock_action", default: "skip_billing_cycle"
    t.boolean "tips_enabled", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "variant_label_text", default: "Choose a variant"
    t.decimal "weekly_rate", precision: 10, scale: 2
    t.index ["active"], name: "index_products_on_active"
    t.index ["allow_customer_preferences"], name: "index_products_on_allow_customer_preferences"
    t.index ["allow_discounts"], name: "index_products_on_allow_discounts"
    t.index ["business_id", "position"], name: "index_products_on_business_id_and_position"
    t.index ["business_id", "rental_category"], name: "index_products_on_business_id_and_rental_category", where: "(product_type = 3)"
    t.index ["business_id"], name: "index_products_on_business_id"
    t.index ["document_template_id"], name: "index_products_on_document_template_id"
    t.index ["featured"], name: "index_products_on_featured"
    t.index ["location_id"], name: "index_products_on_location_id"
    t.index ["rental_availability_schedule"], name: "index_products_on_rental_availability_schedule", using: :gin
    t.index ["tips_enabled"], name: "index_products_on_tips_enabled"
  end

  create_table "promotion_products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.bigint "promotion_id", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_promotion_products_on_product_id"
    t.index ["promotion_id", "product_id"], name: "index_promotion_products_on_promotion_id_and_product_id", unique: true
    t.index ["promotion_id"], name: "index_promotion_products_on_promotion_id"
  end

  create_table "promotion_redemptions", force: :cascade do |t|
    t.bigint "booking_id"
    t.datetime "created_at", null: false
    t.bigint "invoice_id"
    t.bigint "promotion_id", null: false
    t.datetime "redeemed_at"
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_promotion_redemptions_on_booking_id"
    t.index ["invoice_id"], name: "index_promotion_redemptions_on_invoice_id"
    t.index ["promotion_id"], name: "index_promotion_redemptions_on_promotion_id"
    t.index ["tenant_customer_id"], name: "index_promotion_redemptions_on_tenant_customer_id"
  end

  create_table "promotion_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "promotion_id", null: false
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["promotion_id", "service_id"], name: "index_promotion_services_on_promotion_id_and_service_id", unique: true
    t.index ["promotion_id"], name: "index_promotion_services_on_promotion_id"
    t.index ["service_id"], name: "index_promotion_services_on_service_id"
  end

  create_table "promotions", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "allow_discount_codes", default: true, null: false
    t.boolean "applicable_to_products", default: true, null: false
    t.boolean "applicable_to_services", default: true, null: false
    t.bigint "business_id", null: false
    t.string "code"
    t.datetime "created_at", null: false
    t.integer "current_usage", default: 0
    t.text "description"
    t.integer "discount_type", default: 0
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.datetime "end_date"
    t.string "name", null: false
    t.boolean "public_dates", default: false, null: false
    t.datetime "start_date"
    t.datetime "updated_at", null: false
    t.integer "usage_limit"
    t.index ["applicable_to_products"], name: "index_promotions_on_applicable_to_products"
    t.index ["applicable_to_services"], name: "index_promotions_on_applicable_to_services"
    t.index ["business_id"], name: "index_promotions_on_business_id"
    t.index ["code", "business_id"], name: "index_promotions_on_code_and_business_id", unique: true, where: "(code IS NOT NULL)"
    t.index ["public_dates"], name: "index_promotions_on_public_dates"
  end

  create_table "quickbooks_connections", force: :cascade do |t|
    t.text "access_token"
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.string "environment", default: "production", null: false
    t.datetime "last_synced_at"
    t.datetime "last_used_at"
    t.string "realm_id", null: false
    t.text "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.text "scopes"
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_quickbooks_connections_on_active"
    t.index ["business_id"], name: "index_quickbooks_connections_on_business_id", unique: true
    t.index ["realm_id"], name: "index_quickbooks_connections_on_realm_id"
  end

  create_table "quickbooks_export_runs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "error_report", default: {}, null: false
    t.string "export_type", default: "invoices", null: false
    t.jsonb "filters", default: {}, null: false
    t.datetime "finished_at"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["business_id", "created_at"], name: "index_quickbooks_export_runs_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_quickbooks_export_runs_on_business_id"
    t.index ["status"], name: "index_quickbooks_export_runs_on_status"
    t.index ["user_id"], name: "index_quickbooks_export_runs_on_user_id"
  end

  create_table "referral_programs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.decimal "min_purchase_amount", precision: 10, scale: 2, default: "0.0"
    t.decimal "referral_code_discount_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "referrer_reward_type", default: "points", null: false
    t.decimal "referrer_reward_value", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_referral_programs_on_active"
    t.index ["business_id"], name: "index_referral_programs_on_business_id"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "qualification_met_at"
    t.bigint "qualifying_booking_id"
    t.bigint "qualifying_order_id"
    t.string "referral_code", null: false
    t.bigint "referred_tenant_customer_id"
    t.bigint "referrer_id", null: false
    t.datetime "reward_issued_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "referral_code"], name: "index_referrals_on_business_id_and_referral_code", unique: true
    t.index ["business_id"], name: "index_referrals_on_business_id"
    t.index ["qualifying_booking_id"], name: "index_referrals_on_qualifying_booking_id"
    t.index ["qualifying_order_id"], name: "index_referrals_on_qualifying_order_id"
    t.index ["referral_code"], name: "index_referrals_on_referral_code"
    t.index ["referred_tenant_customer_id"], name: "index_referrals_on_referred_tenant_customer_id"
    t.index ["referrer_id"], name: "index_referrals_on_referrer_id"
    t.index ["status"], name: "index_referrals_on_status"
  end

  create_table "rental_bookings", force: :cascade do |t|
    t.datetime "actual_pickup_time"
    t.datetime "actual_return_time"
    t.string "booking_number", null: false
    t.bigint "business_id", null: false
    t.text "condition_notes_checkout"
    t.text "condition_notes_return"
    t.datetime "created_at", null: false
    t.text "customer_notes"
    t.decimal "damage_fee_amount", precision: 10, scale: 2, default: "0.0"
    t.string "deposit_authorization_id"
    t.datetime "deposit_authorization_released_at"
    t.datetime "deposit_authorized_at"
    t.datetime "deposit_captured_at"
    t.datetime "deposit_paid_at"
    t.decimal "deposit_refund_amount", precision: 10, scale: 2
    t.datetime "deposit_refunded_at"
    t.string "deposit_status", default: "pending", null: false
    t.decimal "discount_amount", precision: 10, scale: 2, default: "0.0"
    t.datetime "end_time", null: false
    t.string "guest_access_token"
    t.decimal "late_fee_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "location_id"
    t.integer "lock_version", default: 0, null: false
    t.text "notes"
    t.bigint "product_id", null: false
    t.bigint "product_variant_id"
    t.bigint "promotion_id"
    t.integer "quantity", default: 1, null: false
    t.decimal "rate_amount", precision: 10, scale: 2
    t.integer "rate_quantity"
    t.string "rate_type"
    t.decimal "security_deposit_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "staff_member_id"
    t.datetime "start_time", null: false
    t.string "status", default: "pending_deposit", null: false
    t.string "stripe_deposit_payment_intent_id"
    t.string "stripe_payment_intent_id"
    t.decimal "subtotal", precision: 10, scale: 2
    t.decimal "tax_amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "tenant_customer_id", null: false
    t.decimal "total_amount", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["business_id", "booking_number"], name: "index_rental_bookings_on_business_and_booking_number", unique: true
    t.index ["business_id", "status"], name: "index_rental_bookings_on_business_and_status"
    t.index ["business_id", "status"], name: "index_rental_bookings_on_business_id_and_status"
    t.index ["business_id"], name: "index_rental_bookings_on_business_id"
    t.index ["deposit_authorization_id"], name: "index_rental_bookings_on_deposit_authorization_id"
    t.index ["end_time"], name: "index_rental_bookings_on_end_time_for_overdue", where: "((status)::text = ANY ((ARRAY['checked_out'::character varying, 'overdue'::character varying])::text[]))"
    t.index ["guest_access_token"], name: "index_rental_bookings_on_guest_access_token", unique: true
    t.index ["location_id"], name: "index_rental_bookings_on_location_id"
    t.index ["product_id", "start_time", "end_time"], name: "idx_on_product_id_start_time_end_time_f527c29028"
    t.index ["product_id", "start_time", "end_time"], name: "index_rental_bookings_on_product_and_times"
    t.index ["product_id"], name: "index_rental_bookings_on_product_id"
    t.index ["product_variant_id"], name: "index_rental_bookings_on_product_variant_id"
    t.index ["promotion_id"], name: "index_rental_bookings_on_promotion_id"
    t.index ["staff_member_id"], name: "index_rental_bookings_on_staff_member_id"
    t.index ["status", "end_time"], name: "index_rental_bookings_on_status_and_end_time"
    t.index ["stripe_deposit_payment_intent_id"], name: "index_rental_bookings_on_stripe_payment_intent"
    t.index ["tenant_customer_id", "status"], name: "index_rental_bookings_on_tenant_customer_id_and_status"
    t.index ["tenant_customer_id"], name: "index_rental_bookings_on_tenant_customer_id"
  end

  create_table "rental_condition_reports", force: :cascade do |t|
    t.jsonb "checklist_items", default: []
    t.string "condition_rating"
    t.datetime "created_at", null: false
    t.decimal "damage_assessment_amount", precision: 10, scale: 2, default: "0.0"
    t.text "damage_description"
    t.text "notes"
    t.bigint "rental_booking_id", null: false
    t.string "report_type", null: false
    t.bigint "staff_member_id"
    t.datetime "updated_at", null: false
    t.index ["rental_booking_id", "report_type"], name: "idx_on_rental_booking_id_report_type_8fb05c2c2e"
    t.index ["rental_booking_id"], name: "index_rental_condition_reports_on_rental_booking_id"
    t.index ["staff_member_id"], name: "index_rental_condition_reports_on_staff_member_id"
  end

  create_table "service_job_forms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_form_template_id", null: false
    t.boolean "required", default: false, null: false
    t.bigint "service_id", null: false
    t.integer "timing", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["job_form_template_id"], name: "index_service_job_forms_on_job_form_template_id"
    t.index ["service_id", "job_form_template_id"], name: "idx_service_job_forms_unique", unique: true
    t.index ["service_id"], name: "index_service_job_forms_on_service_id"
  end

  create_table "service_templates", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "industry"
    t.string "name", null: false
    t.datetime "published_at"
    t.jsonb "structure"
    t.integer "template_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_templates_on_active"
    t.index ["industry"], name: "index_service_templates_on_industry"
    t.index ["name"], name: "index_service_templates_on_name"
    t.index ["template_type"], name: "index_service_templates_on_template_type"
  end

  create_table "service_variants", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.integer "duration", null: false
    t.string "name", null: false
    t.integer "position", default: 0
    t.decimal "price", precision: 10, scale: 2, null: false
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "name", "duration"], name: "index_service_variants_on_service_id_name_duration", unique: true
    t.index ["service_id"], name: "index_service_variants_on_service_id"
  end

  create_table "services", force: :cascade do |t|
    t.boolean "active", default: true
    t.boolean "allow_customer_preferences", default: true, null: false
    t.boolean "allow_discounts", default: true, null: false
    t.jsonb "availability", default: {}, null: false
    t.jsonb "availability_settings"
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_from_estimate_id"
    t.text "description"
    t.bigint "document_template_id"
    t.integer "duration", null: false
    t.boolean "enforce_service_availability", default: true, null: false
    t.datetime "event_starts_at"
    t.boolean "featured"
    t.integer "max_bookings"
    t.integer "min_bookings"
    t.string "name", null: false
    t.integer "position", default: 0
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "quickbooks_item_id"
    t.integer "service_type"
    t.integer "spots"
    t.string "subscription_billing_cycle", default: "monthly"
    t.decimal "subscription_discount_percentage", precision: 5, scale: 2
    t.boolean "subscription_enabled", default: false, null: false
    t.string "subscription_rebooking_preference", default: "same_day_next_month"
    t.boolean "tip_mailer_if_no_tip_received", default: true, null: false
    t.boolean "tips_enabled", default: false, null: false
    t.datetime "updated_at", null: false
    t.boolean "video_enabled", default: false, null: false
    t.integer "video_provider", default: 0, null: false
    t.index ["allow_customer_preferences"], name: "index_services_on_allow_customer_preferences"
    t.index ["allow_discounts"], name: "index_services_on_allow_discounts"
    t.index ["business_id", "position"], name: "index_services_on_business_id_and_position"
    t.index ["business_id"], name: "index_services_on_business_id"
    t.index ["created_from_estimate_id"], name: "index_services_on_created_from_estimate_id"
    t.index ["document_template_id"], name: "index_services_on_document_template_id"
    t.index ["event_starts_at"], name: "index_services_on_event_starts_at_for_events", where: "(service_type = 2)"
    t.index ["name", "business_id"], name: "index_services_on_name_and_business_id", unique: true
    t.index ["quickbooks_item_id"], name: "index_services_on_quickbooks_item_id"
    t.index ["tips_enabled"], name: "index_services_on_tips_enabled"
    t.index ["video_enabled"], name: "index_services_on_video_enabled"
  end

  create_table "services_staff_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "service_id", null: false
    t.bigint "staff_member_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "staff_member_id"], name: "index_services_staff_members_uniqueness", unique: true
    t.index ["service_id"], name: "index_services_staff_members_on_service_id"
    t.index ["staff_member_id"], name: "index_services_staff_members_on_staff_member_id"
  end

  create_table "setup_reminder_dismissals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dismissed_at", null: false
    t.string "task_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "task_key"], name: "index_setup_reminder_dismissals_on_user_id_and_task_key", unique: true
    t.index ["user_id"], name: "index_setup_reminder_dismissals_on_user_id"
  end

  create_table "shipping_methods", force: :cascade do |t|
    t.boolean "active", default: true
    t.bigint "business_id", null: false
    t.decimal "cost", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_shipping_methods_on_active"
    t.index ["business_id"], name: "index_shipping_methods_on_business_id"
    t.index ["name", "business_id"], name: "index_shipping_methods_on_name_and_business_id", unique: true
  end

  create_table "sms_links", force: :cascade do |t|
    t.integer "click_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "last_clicked_at"
    t.text "original_url", null: false
    t.string "short_code", null: false
    t.jsonb "tracking_params", default: {}
    t.datetime "updated_at", null: false
    t.index ["short_code"], name: "index_sms_links_on_short_code", unique: true
  end

  create_table "sms_messages", force: :cascade do |t|
    t.bigint "booking_id"
    t.bigint "business_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.text "error_message"
    t.string "external_id"
    t.bigint "marketing_campaign_id"
    t.text "phone_number"
    t.datetime "sent_at"
    t.integer "status", default: 0, null: false
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_sms_messages_on_booking_id"
    t.index ["business_id", "created_at"], name: "index_sms_messages_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_sms_messages_on_business_id"
    t.index ["external_id"], name: "index_sms_messages_on_external_id"
    t.index ["marketing_campaign_id"], name: "index_sms_messages_on_marketing_campaign_id"
    t.index ["phone_number"], name: "index_sms_messages_on_phone_number"
    t.index ["status"], name: "index_sms_messages_on_status"
    t.index ["tenant_customer_id", "created_at"], name: "index_sms_messages_on_tenant_customer_id_and_created_at"
    t.index ["tenant_customer_id"], name: "index_sms_messages_on_tenant_customer_id"
  end

  create_table "sms_opt_in_invitations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "context", null: false
    t.datetime "created_at", null: false
    t.string "phone_number", null: false
    t.datetime "responded_at"
    t.string "response"
    t.datetime "sent_at", null: false
    t.boolean "successful_opt_in", default: false, null: false
    t.bigint "tenant_customer_id"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_sms_opt_in_invitations_on_business_id"
    t.index ["phone_number", "business_id", "sent_at"], name: "idx_on_phone_number_business_id_sent_at_175e5cb6a6"
    t.index ["phone_number", "business_id"], name: "index_sms_opt_in_invitations_on_phone_number_and_business_id"
    t.index ["responded_at"], name: "index_sms_opt_in_invitations_on_responded_at"
    t.index ["sent_at"], name: "index_sms_opt_in_invitations_on_sent_at"
    t.index ["successful_opt_in"], name: "index_sms_opt_in_invitations_on_successful_opt_in"
    t.index ["tenant_customer_id"], name: "index_sms_opt_in_invitations_on_tenant_customer_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "staff_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "service_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["service_id"], name: "index_staff_assignments_on_service_id"
    t.index ["user_id"], name: "index_staff_assignments_on_user_id"
  end

  create_table "staff_members", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "adp_department_code"
    t.string "adp_employee_id"
    t.string "adp_job_code"
    t.string "adp_pay_code"
    t.jsonb "availability"
    t.text "bio"
    t.bigint "business_id", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.bigint "default_calendar_connection_id"
    t.string "email"
    t.string "name", null: false
    t.string "phone"
    t.string "position"
    t.string "specialties", default: [], array: true
    t.integer "status"
    t.string "timezone", default: "UTC"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["adp_employee_id"], name: "index_staff_members_on_adp_employee_id"
    t.index ["business_id"], name: "index_staff_members_on_business_id"
    t.index ["default_calendar_connection_id"], name: "index_staff_members_on_default_calendar_connection_id"
    t.index ["user_id"], name: "index_staff_members_on_user_id"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "movement_type"
    t.text "notes"
    t.bigint "product_id", null: false
    t.integer "quantity"
    t.string "reference_id"
    t.string "reference_type"
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_stock_movements_on_product_id"
  end

  create_table "stock_reservations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "order_id"
    t.bigint "product_variant_id"
    t.integer "quantity"
    t.datetime "updated_at", null: false
  end

  create_table "subscription_transactions", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2
    t.bigint "booking_id"
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_subscription_id", null: false
    t.text "failure_reason"
    t.bigint "invoice_id"
    t.integer "loyalty_points_awarded", default: 0
    t.jsonb "metadata"
    t.datetime "next_retry_at"
    t.text "notes"
    t.bigint "order_id"
    t.bigint "payment_id"
    t.date "processed_date", null: false
    t.integer "retry_count", default: 0
    t.integer "status", default: 0, null: false
    t.string "stripe_invoice_id"
    t.bigint "tenant_customer_id", null: false
    t.string "transaction_type", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_subscription_transactions_on_booking_id"
    t.index ["business_id", "status"], name: "index_subscription_transactions_on_business_id_and_status"
    t.index ["business_id"], name: "index_subscription_transactions_on_business_id"
    t.index ["customer_subscription_id", "processed_date"], name: "idx_on_customer_subscription_id_processed_date_6becfeb405"
    t.index ["customer_subscription_id"], name: "index_subscription_transactions_on_customer_subscription_id"
    t.index ["invoice_id"], name: "index_subscription_transactions_on_invoice_id"
    t.index ["next_retry_at"], name: "index_subscription_transactions_on_next_retry_at"
    t.index ["order_id"], name: "index_subscription_transactions_on_order_id"
    t.index ["payment_id"], name: "index_subscription_transactions_on_payment_id"
    t.index ["processed_date"], name: "index_subscription_transactions_on_processed_date"
    t.index ["tenant_customer_id"], name: "index_subscription_transactions_on_tenant_customer_id"
    t.index ["transaction_type", "status"], name: "index_subscription_transactions_on_transaction_type_and_status"
  end

  create_table "tax_rates", force: :cascade do |t|
    t.boolean "applies_to_shipping", default: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.decimal "rate", precision: 10, scale: 4, null: false
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_tax_rates_on_business_id"
    t.index ["name", "business_id"], name: "index_tax_rates_on_name_and_business_id", unique: true
  end

  create_table "tenant_customers", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "address"
    t.bigint "business_id", null: false
    t.string "constant_contact_id"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "email_marketing_opt_out"
    t.datetime "email_marketing_synced_at"
    t.string "first_name"
    t.datetime "last_appointment"
    t.string "last_name"
    t.string "mailchimp_list_id"
    t.string "mailchimp_subscriber_hash"
    t.text "notes"
    t.string "phone"
    t.boolean "phone_marketing_opt_out", default: false, null: false
    t.boolean "phone_opt_in", default: false, null: false
    t.datetime "phone_opt_in_at"
    t.string "quickbooks_customer_id"
    t.jsonb "sms_opted_out_businesses", default: []
    t.string "stripe_customer_id"
    t.string "unsubscribe_token"
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index "business_id, lower((email)::text)", name: "index_tenant_customers_on_business_id_and_lower_email", unique: true
    t.index "lower((email)::text)", name: "index_tenant_customers_on_lower_email"
    t.index ["business_id", "phone"], name: "index_tenant_customers_on_business_phone_for_users", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["business_id"], name: "index_tenant_customers_on_business_id"
    t.index ["constant_contact_id"], name: "index_tenant_customers_on_constant_contact_id"
    t.index ["email", "business_id"], name: "index_tenant_customers_on_email_and_business_id", unique: true
    t.index ["email_marketing_synced_at"], name: "index_tenant_customers_on_email_marketing_synced_at"
    t.index ["mailchimp_subscriber_hash"], name: "index_tenant_customers_on_mailchimp_subscriber_hash"
    t.index ["quickbooks_customer_id"], name: "index_tenant_customers_on_quickbooks_customer_id"
    t.index ["sms_opted_out_businesses"], name: "index_tenant_customers_on_sms_opted_out_businesses", using: :gin
    t.index ["stripe_customer_id"], name: "index_tenant_customers_on_stripe_customer_id", unique: true
    t.index ["unsubscribe_token"], name: "index_tenant_customers_on_unsubscribe_token", unique: true
    t.index ["user_id"], name: "index_tenant_customers_on_user_id"
  end

  create_table "test_models", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "tip_configurations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.boolean "custom_tip_enabled", default: true, null: false
    t.json "default_tip_percentages", default: [15, 18, 20], null: false
    t.text "tip_message"
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_tip_configurations_on_business_id"
  end

  create_table "tips", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.bigint "booking_id", null: false
    t.decimal "business_amount", precision: 10, scale: 2, null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.text "failure_reason"
    t.datetime "paid_at"
    t.decimal "platform_fee_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "status", default: 0, null: false
    t.string "stripe_charge_id"
    t.string "stripe_customer_id"
    t.decimal "stripe_fee_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "stripe_payment_intent_id"
    t.bigint "tenant_customer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_tips_on_booking_id"
    t.index ["business_amount"], name: "index_tips_on_business_amount"
    t.index ["business_id", "status"], name: "index_tips_on_business_id_and_status"
    t.index ["business_id"], name: "index_tips_on_business_id"
    t.index ["paid_at"], name: "index_tips_on_paid_at"
    t.index ["platform_fee_amount"], name: "index_tips_on_platform_fee_amount"
    t.index ["stripe_fee_amount"], name: "index_tips_on_stripe_fee_amount"
    t.index ["stripe_payment_intent_id"], name: "index_tips_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
    t.index ["tenant_customer_id"], name: "index_tips_on_tenant_customer_id"
    t.check_constraint "amount > 0::numeric", name: "tips_amount_positive"
  end

  create_table "user_sidebar_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "item_key", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "visible", default: true, null: false
    t.index ["user_id", "item_key"], name: "index_user_sidebar_items_on_user_id_and_item_key", unique: true
    t.index ["user_id"], name: "index_user_sidebar_items_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true
    t.bigint "business_id"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", null: false
    t.boolean "email_marketing_opt_out"
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_policy_notification_at"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.jsonb "notification_preferences"
    t.string "phone"
    t.boolean "phone_marketing_opt_out", default: false, null: false
    t.boolean "phone_opt_in", default: false, null: false
    t.datetime "phone_opt_in_at"
    t.string "referral_source_code"
    t.datetime "remember_created_at"
    t.boolean "requires_policy_acceptance", default: false
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 3
    t.string "session_token"
    t.integer "sign_in_count", default: 0, null: false
    t.bigint "staff_member_id"
    t.string "unconfirmed_email"
    t.string "unsubscribe_token"
    t.datetime "unsubscribed_at"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["current_sign_in_at"], name: "index_users_on_current_sign_in_at"
    t.index ["email", "role"], name: "index_users_on_email_and_role"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_sign_in_at"], name: "index_users_on_last_sign_in_at"
    t.index ["requires_policy_acceptance"], name: "index_users_on_requires_policy_acceptance"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["session_token"], name: "index_users_on_session_token"
    t.index ["unsubscribe_token"], name: "index_users_on_unsubscribe_token", unique: true
  end

  create_table "video_meeting_connections", force: :cascade do |t|
    t.text "access_token"
    t.boolean "active", default: true, null: false
    t.bigint "business_id", null: false
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.integer "provider", default: 0, null: false
    t.text "refresh_token"
    t.text "scopes"
    t.bigint "staff_member_id", null: false
    t.datetime "token_expires_at"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_video_meeting_connections_on_active"
    t.index ["business_id", "active"], name: "idx_video_connections_business_active"
    t.index ["business_id", "staff_member_id", "provider"], name: "idx_video_meeting_connections_unique", unique: true
    t.index ["business_id"], name: "index_video_meeting_connections_on_business_id"
    t.index ["staff_member_id", "provider", "active"], name: "idx_video_connections_staff_provider_active"
    t.index ["staff_member_id"], name: "index_video_meeting_connections_on_staff_member_id"
  end

  create_table "website_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.json "default_theme", default: {}, null: false
    t.text "description"
    t.string "industry", null: false
    t.string "name", null: false
    t.text "preview_image_url"
    t.boolean "requires_premium", default: false, null: false
    t.json "structure", default: {}, null: false
    t.integer "template_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active", "requires_premium"], name: "index_website_templates_on_active_and_requires_premium"
    t.index ["industry"], name: "index_website_templates_on_industry"
    t.index ["template_type"], name: "index_website_templates_on_template_type"
  end

  create_table "website_themes", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.bigint "business_id", null: false
    t.json "color_scheme", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "custom_css"
    t.json "layout_config", default: {}, null: false
    t.string "name", null: false
    t.json "typography", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "active"], name: "index_website_themes_on_business_id_and_active"
    t.index ["business_id"], name: "index_website_themes_on_business_id"
    t.index ["name"], name: "index_website_themes_on_name"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "adp_payroll_export_configs", "businesses"
  add_foreign_key "adp_payroll_export_runs", "businesses"
  add_foreign_key "adp_payroll_export_runs", "users"
  add_foreign_key "auth_tokens", "users"
  add_foreign_key "authentication_bridges", "users"
  add_foreign_key "booking_policies", "businesses", on_delete: :cascade
  add_foreign_key "booking_product_add_ons", "bookings", on_delete: :cascade
  add_foreign_key "booking_product_add_ons", "product_variants"
  add_foreign_key "bookings", "businesses", on_delete: :cascade
  add_foreign_key "bookings", "promotions", on_delete: :nullify
  add_foreign_key "bookings", "service_variants"
  add_foreign_key "bookings", "services", on_delete: :nullify
  add_foreign_key "bookings", "staff_members", on_delete: :nullify
  add_foreign_key "bookings", "tenant_customers", on_delete: :nullify
  add_foreign_key "businesses", "service_templates"
  add_foreign_key "calendar_connections", "businesses"
  add_foreign_key "calendar_connections", "staff_members"
  add_foreign_key "calendar_event_mappings", "bookings"
  add_foreign_key "calendar_event_mappings", "calendar_connections"
  add_foreign_key "calendar_sync_logs", "calendar_event_mappings"
  add_foreign_key "campaign_recipients", "marketing_campaigns"
  add_foreign_key "campaign_recipients", "tenant_customers"
  add_foreign_key "client_businesses", "businesses", on_delete: :cascade
  add_foreign_key "client_businesses", "users"
  add_foreign_key "client_document_events", "businesses"
  add_foreign_key "client_document_events", "client_documents"
  add_foreign_key "client_documents", "businesses"
  add_foreign_key "client_documents", "document_templates"
  add_foreign_key "client_documents", "invoices"
  add_foreign_key "client_documents", "tenant_customers"
  add_foreign_key "csv_import_runs", "businesses"
  add_foreign_key "csv_import_runs", "users"
  add_foreign_key "customer_subscriptions", "businesses", on_delete: :cascade
  add_foreign_key "customer_subscriptions", "product_variants"
  add_foreign_key "customer_subscriptions", "products"
  add_foreign_key "customer_subscriptions", "services"
  add_foreign_key "customer_subscriptions", "staff_members", column: "preferred_staff_member_id"
  add_foreign_key "customer_subscriptions", "tenant_customers"
  add_foreign_key "discount_codes", "businesses", on_delete: :cascade
  add_foreign_key "discount_codes", "referrals", column: "generated_by_referral_id"
  add_foreign_key "discount_codes", "tenant_customers"
  add_foreign_key "discount_codes", "tenant_customers", column: "used_by_customer_id", on_delete: :nullify
  add_foreign_key "document_signatures", "businesses"
  add_foreign_key "document_signatures", "client_documents"
  add_foreign_key "document_templates", "businesses"
  add_foreign_key "email_marketing_connections", "businesses"
  add_foreign_key "email_marketing_sync_logs", "businesses"
  add_foreign_key "email_marketing_sync_logs", "email_marketing_connections"
  add_foreign_key "estimate_items", "estimates"
  add_foreign_key "estimate_items", "product_variants"
  add_foreign_key "estimate_items", "products"
  add_foreign_key "estimate_items", "services"
  add_foreign_key "estimate_messages", "businesses"
  add_foreign_key "estimate_messages", "estimates"
  add_foreign_key "estimate_versions", "estimates"
  add_foreign_key "estimates", "bookings"
  add_foreign_key "estimates", "businesses"
  add_foreign_key "estimates", "tenant_customers"
  add_foreign_key "external_calendar_events", "calendar_connections"
  add_foreign_key "gallery_photos", "businesses"
  add_foreign_key "integration_credentials", "businesses", on_delete: :cascade
  add_foreign_key "integrations", "businesses", on_delete: :cascade
  add_foreign_key "invalidated_sessions", "users", on_delete: :cascade
  add_foreign_key "invoices", "bookings", on_delete: :nullify
  add_foreign_key "invoices", "businesses", on_delete: :cascade
  add_foreign_key "invoices", "orders"
  add_foreign_key "invoices", "promotions"
  add_foreign_key "invoices", "shipping_methods"
  add_foreign_key "invoices", "tax_rates"
  add_foreign_key "invoices", "tenant_customers", on_delete: :cascade
  add_foreign_key "job_attachments", "businesses"
  add_foreign_key "job_attachments", "users", column: "uploaded_by_user_id"
  add_foreign_key "job_form_submissions", "bookings"
  add_foreign_key "job_form_submissions", "businesses"
  add_foreign_key "job_form_submissions", "job_form_templates"
  add_foreign_key "job_form_submissions", "staff_members"
  add_foreign_key "job_form_submissions", "users", column: "approved_by_user_id"
  add_foreign_key "job_form_submissions", "users", column: "submitted_by_user_id"
  add_foreign_key "job_form_templates", "businesses"
  add_foreign_key "line_items", "product_variants"
  add_foreign_key "line_items", "services", on_delete: :nullify
  add_foreign_key "line_items", "staff_members", on_delete: :nullify
  add_foreign_key "locations", "businesses", on_delete: :cascade
  add_foreign_key "loyalty_programs", "businesses", on_delete: :cascade
  add_foreign_key "loyalty_redemptions", "bookings", on_delete: :nullify
  add_foreign_key "loyalty_redemptions", "businesses", on_delete: :cascade
  add_foreign_key "loyalty_redemptions", "loyalty_rewards", on_delete: :cascade
  add_foreign_key "loyalty_redemptions", "orders", on_delete: :nullify
  add_foreign_key "loyalty_redemptions", "tenant_customers", on_delete: :cascade
  add_foreign_key "loyalty_rewards", "businesses", on_delete: :cascade
  add_foreign_key "loyalty_rewards", "loyalty_programs", on_delete: :cascade
  add_foreign_key "loyalty_transactions", "bookings", column: "related_booking_id"
  add_foreign_key "loyalty_transactions", "businesses", on_delete: :cascade
  add_foreign_key "loyalty_transactions", "orders", column: "related_order_id"
  add_foreign_key "loyalty_transactions", "referrals", column: "related_referral_id"
  add_foreign_key "loyalty_transactions", "tenant_customers", on_delete: :cascade
  add_foreign_key "marketing_campaigns", "businesses", on_delete: :cascade
  add_foreign_key "marketing_campaigns", "promotions"
  add_foreign_key "notification_templates", "businesses", on_delete: :cascade
  add_foreign_key "orders", "bookings", on_delete: :nullify
  add_foreign_key "orders", "businesses", on_delete: :cascade
  add_foreign_key "orders", "customer_subscriptions"
  add_foreign_key "orders", "shipping_methods"
  add_foreign_key "orders", "tax_rates"
  add_foreign_key "orders", "tenant_customers", on_delete: :nullify
  add_foreign_key "page_sections", "pages"
  add_foreign_key "page_versions", "pages"
  add_foreign_key "page_versions", "users", column: "created_by_id"
  add_foreign_key "pages", "businesses", on_delete: :cascade
  add_foreign_key "payments", "businesses", on_delete: :cascade
  add_foreign_key "payments", "invoices", on_delete: :nullify
  add_foreign_key "payments", "orders", on_delete: :nullify
  add_foreign_key "payments", "tenant_customers", on_delete: :nullify
  add_foreign_key "pending_sms_notifications", "bookings"
  add_foreign_key "pending_sms_notifications", "businesses", on_delete: :cascade
  add_foreign_key "pending_sms_notifications", "invoices"
  add_foreign_key "pending_sms_notifications", "orders"
  add_foreign_key "pending_sms_notifications", "tenant_customers", on_delete: :cascade
  add_foreign_key "policy_acceptances", "users"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "businesses", on_delete: :cascade
  add_foreign_key "products", "document_templates"
  add_foreign_key "products", "locations"
  add_foreign_key "promotion_products", "products", on_delete: :cascade
  add_foreign_key "promotion_products", "promotions", on_delete: :cascade
  add_foreign_key "promotion_redemptions", "bookings", on_delete: :cascade
  add_foreign_key "promotion_redemptions", "invoices"
  add_foreign_key "promotion_redemptions", "promotions"
  add_foreign_key "promotion_redemptions", "tenant_customers"
  add_foreign_key "promotion_services", "promotions", on_delete: :cascade
  add_foreign_key "promotion_services", "services", on_delete: :cascade
  add_foreign_key "promotions", "businesses", on_delete: :cascade
  add_foreign_key "quickbooks_connections", "businesses"
  add_foreign_key "quickbooks_export_runs", "businesses"
  add_foreign_key "quickbooks_export_runs", "users"
  add_foreign_key "referral_programs", "businesses", on_delete: :cascade
  add_foreign_key "referrals", "bookings", column: "qualifying_booking_id"
  add_foreign_key "referrals", "businesses", on_delete: :cascade
  add_foreign_key "referrals", "orders", column: "qualifying_order_id"
  add_foreign_key "referrals", "tenant_customers", column: "referred_tenant_customer_id"
  add_foreign_key "referrals", "users", column: "referrer_id"
  add_foreign_key "rental_bookings", "businesses"
  add_foreign_key "rental_bookings", "locations"
  add_foreign_key "rental_bookings", "product_variants"
  add_foreign_key "rental_bookings", "products"
  add_foreign_key "rental_bookings", "promotions"
  add_foreign_key "rental_bookings", "staff_members"
  add_foreign_key "rental_bookings", "tenant_customers"
  add_foreign_key "rental_condition_reports", "rental_bookings"
  add_foreign_key "rental_condition_reports", "staff_members"
  add_foreign_key "service_job_forms", "job_form_templates"
  add_foreign_key "service_job_forms", "services"
  add_foreign_key "service_variants", "services"
  add_foreign_key "services", "businesses", on_delete: :cascade
  add_foreign_key "services", "document_templates"
  add_foreign_key "services", "estimates", column: "created_from_estimate_id"
  add_foreign_key "services_staff_members", "services", on_delete: :cascade
  add_foreign_key "services_staff_members", "staff_members", on_delete: :cascade
  add_foreign_key "setup_reminder_dismissals", "users"
  add_foreign_key "shipping_methods", "businesses", on_delete: :cascade
  add_foreign_key "sms_messages", "bookings", on_delete: :cascade
  add_foreign_key "sms_messages", "businesses"
  add_foreign_key "sms_messages", "marketing_campaigns"
  add_foreign_key "sms_messages", "tenant_customers"
  add_foreign_key "sms_opt_in_invitations", "businesses"
  add_foreign_key "sms_opt_in_invitations", "tenant_customers"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "staff_assignments", "services"
  add_foreign_key "staff_assignments", "users"
  add_foreign_key "staff_members", "businesses", on_delete: :cascade
  add_foreign_key "staff_members", "calendar_connections", column: "default_calendar_connection_id"
  add_foreign_key "staff_members", "users", on_delete: :nullify
  add_foreign_key "stock_movements", "products"
  add_foreign_key "stock_reservations", "orders"
  add_foreign_key "stock_reservations", "product_variants", on_delete: :cascade
  add_foreign_key "subscription_transactions", "bookings"
  add_foreign_key "subscription_transactions", "businesses", on_delete: :cascade
  add_foreign_key "subscription_transactions", "customer_subscriptions"
  add_foreign_key "subscription_transactions", "invoices"
  add_foreign_key "subscription_transactions", "orders"
  add_foreign_key "subscription_transactions", "payments"
  add_foreign_key "subscription_transactions", "tenant_customers"
  add_foreign_key "tax_rates", "businesses", on_delete: :cascade
  add_foreign_key "tenant_customers", "businesses", on_delete: :cascade
  add_foreign_key "tenant_customers", "users"
  add_foreign_key "tip_configurations", "businesses"
  add_foreign_key "tips", "bookings"
  add_foreign_key "tips", "businesses"
  add_foreign_key "tips", "tenant_customers"
  add_foreign_key "user_sidebar_items", "users"
  add_foreign_key "users", "businesses"
  add_foreign_key "users", "staff_members"
  add_foreign_key "video_meeting_connections", "businesses"
  add_foreign_key "video_meeting_connections", "staff_members"
  add_foreign_key "website_themes", "businesses"
end
