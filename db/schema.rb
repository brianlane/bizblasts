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

ActiveRecord::Schema[8.0].define(version: 2025_08_07_173511) do
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

  create_table "blog_posts", force: :cascade do |t|
    t.string "title", null: false
    t.string "slug", null: false
    t.text "excerpt", null: false
    t.text "content", null: false
    t.string "author_name"
    t.string "author_email"
    t.string "category"
    t.string "featured_image_url"
    t.boolean "published", default: false
    t.datetime "published_at"
    t.date "release_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_blog_posts_on_category"
    t.index ["published"], name: "index_blog_posts_on_published"
    t.index ["published_at"], name: "index_blog_posts_on_published_at"
    t.index ["slug"], name: "index_blog_posts_on_slug", unique: true
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
    t.integer "min_advance_mins", default: 0
    t.boolean "auto_confirm_bookings", default: false, null: false
    t.boolean "use_fixed_intervals", default: false, null: false
    t.integer "interval_mins", default: 30
    t.index ["business_id"], name: "index_booking_policies_on_business_id"
    t.index ["min_advance_mins"], name: "index_booking_policies_on_min_advance_mins"
    t.index ["use_fixed_intervals"], name: "index_booking_policies_on_use_fixed_intervals"
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
    t.string "applied_promo_code"
    t.decimal "promo_discount_amount", precision: 10, scale: 2
    t.string "promo_code_type"
    t.datetime "tip_reminder_sent_at"
    t.integer "cancelled_by"
    t.boolean "manager_override"
    t.bigint "service_variant_id"
    t.integer "calendar_event_status", default: 0
    t.string "calendar_event_id"
    t.boolean "review_request_suppressed", default: false, null: false
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
    t.boolean "domain_coverage_applied", default: false
    t.decimal "domain_cost_covered", precision: 8, scale: 2
    t.date "domain_renewal_date"
    t.text "domain_coverage_notes"
    t.boolean "domain_auto_renewal_enabled", default: false
    t.date "domain_coverage_expires_at"
    t.string "domain_registrar"
    t.date "domain_registration_date"
    t.boolean "referral_program_enabled", default: false, null: false
    t.boolean "loyalty_program_enabled", default: false, null: false
    t.decimal "points_per_dollar", precision: 8, scale: 2, default: "1.0", null: false
    t.decimal "points_per_service", precision: 8, scale: 2, default: "0.0", null: false
    t.decimal "points_per_product", precision: 8, scale: 2, default: "0.0", null: false
    t.integer "platform_loyalty_points", default: 0, null: false
    t.string "platform_referral_code"
    t.boolean "subscription_discount_enabled", default: false, null: false
    t.string "subscription_discount_type", default: "percentage"
    t.decimal "subscription_discount_value", precision: 10, scale: 2, default: "0.0"
    t.text "subscription_discount_message"
    t.string "template_applied"
    t.boolean "stock_management_enabled", default: true, null: false
    t.string "google_place_id"
    t.index ["description"], name: "index_businesses_on_description"
    t.index ["domain_auto_renewal_enabled"], name: "index_businesses_on_domain_auto_renewal_enabled"
    t.index ["domain_coverage_applied"], name: "index_businesses_on_domain_coverage_applied"
    t.index ["domain_coverage_expires_at"], name: "index_businesses_on_domain_coverage_expires_at"
    t.index ["domain_renewal_date"], name: "index_businesses_on_domain_renewal_date"
    t.index ["host_type"], name: "index_businesses_on_host_type"
    t.index ["hostname"], name: "index_businesses_on_hostname", unique: true
    t.index ["name"], name: "index_businesses_on_name"
    t.index ["platform_referral_code"], name: "index_businesses_on_platform_referral_code", unique: true
    t.index ["service_template_id"], name: "index_businesses_on_service_template_id"
    t.index ["status"], name: "index_businesses_on_status"
    t.index ["stock_management_enabled"], name: "index_businesses_on_stock_management_enabled"
    t.index ["stripe_account_id"], name: "index_businesses_on_stripe_account_id", unique: true
    t.index ["stripe_customer_id"], name: "index_businesses_on_stripe_customer_id", unique: true
    t.index ["subscription_discount_enabled"], name: "index_businesses_on_subscription_discount_enabled"
    t.check_constraint "subscription_discount_value >= 0::numeric", name: "businesses_subscription_discount_value_positive"
  end

  create_table "calendar_connections", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "staff_member_id", null: false
    t.integer "provider", null: false
    t.string "uid"
    t.text "access_token"
    t.text "refresh_token"
    t.datetime "token_expires_at"
    t.text "scopes"
    t.string "sync_token"
    t.datetime "connected_at"
    t.datetime "last_synced_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "caldav_username"
    t.text "caldav_password"
    t.string "caldav_url"
    t.string "caldav_provider"
    t.index ["active"], name: "index_calendar_connections_on_active"
    t.index ["business_id", "staff_member_id", "provider"], name: "index_calendar_connections_on_business_staff_provider"
    t.index ["business_id"], name: "index_calendar_connections_on_business_id"
    t.index ["last_synced_at"], name: "index_calendar_connections_on_last_synced_at"
    t.index ["staff_member_id"], name: "index_calendar_connections_on_staff_member_id"
  end

  create_table "calendar_event_mappings", force: :cascade do |t|
    t.bigint "booking_id", null: false
    t.bigint "calendar_connection_id", null: false
    t.string "external_event_id", null: false
    t.string "external_calendar_id"
    t.integer "status", default: 0, null: false
    t.datetime "last_synced_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id", "calendar_connection_id"], name: "index_calendar_event_mappings_on_booking_connection"
    t.index ["booking_id"], name: "index_calendar_event_mappings_on_booking_id"
    t.index ["calendar_connection_id"], name: "index_calendar_event_mappings_on_calendar_connection_id"
    t.index ["external_event_id"], name: "index_calendar_event_mappings_on_external_event_id"
    t.index ["status"], name: "index_calendar_event_mappings_on_status"
  end

  create_table "calendar_sync_logs", force: :cascade do |t|
    t.bigint "calendar_event_mapping_id", null: false
    t.integer "action", null: false
    t.integer "outcome", null: false
    t.text "message"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_calendar_sync_logs_on_action"
    t.index ["calendar_event_mapping_id"], name: "index_calendar_sync_logs_on_calendar_event_mapping_id"
    t.index ["created_at"], name: "index_calendar_sync_logs_on_created_at"
    t.index ["metadata"], name: "index_calendar_sync_logs_on_metadata", using: :gin
    t.index ["outcome"], name: "index_calendar_sync_logs_on_outcome"
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

  create_table "client_businesses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_client_businesses_on_business_id"
    t.index ["user_id", "business_id"], name: "index_client_businesses_on_user_id_and_business_id", unique: true
    t.index ["user_id"], name: "index_client_businesses_on_user_id"
  end

  create_table "customer_subscriptions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.bigint "product_id"
    t.bigint "service_id"
    t.bigint "product_variant_id"
    t.string "subscription_type", null: false
    t.integer "status", default: 0, null: false
    t.integer "quantity", default: 1, null: false
    t.date "next_billing_date", null: false
    t.integer "billing_day_of_month", null: false
    t.date "last_processed_date"
    t.integer "service_rebooking_preference"
    t.time "preferred_time_slot"
    t.bigint "preferred_staff_member_id"
    t.integer "out_of_stock_action", default: 0
    t.decimal "subscription_price", precision: 10, scale: 2, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "cancelled_at"
    t.text "cancellation_reason"
    t.string "stripe_subscription_id"
    t.string "customer_out_of_stock_preference"
    t.string "customer_rebooking_preference"
    t.boolean "allow_customer_preferences", default: true, null: false
    t.string "frequency", default: "monthly", null: false
    t.string "customer_rebooking_option", default: "business_default"
    t.json "customer_preferences"
    t.text "failure_reason"
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
    t.bigint "business_id", null: false
    t.string "code", null: false
    t.string "discount_type", null: false
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.boolean "single_use", default: true, null: false
    t.bigint "used_by_customer_id"
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.integer "usage_count", default: 0, null: false
    t.integer "max_usage", default: 1
    t.bigint "generated_by_referral_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "points_redeemed", default: 0, null: false
    t.string "stripe_coupon_id"
    t.bigint "tenant_customer_id"
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

  create_table "estimate_items", force: :cascade do |t|
    t.bigint "estimate_id", null: false
    t.bigint "service_id"
    t.string "description"
    t.integer "qty"
    t.decimal "cost_rate", precision: 10, scale: 2
    t.decimal "tax_rate", precision: 10, scale: 2
    t.decimal "total", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["estimate_id"], name: "index_estimate_items_on_estimate_id"
    t.index ["service_id"], name: "index_estimate_items_on_service_id"
  end

  create_table "estimates", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.datetime "proposed_start_time"
    t.datetime "proposed_end_time"
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.string "address"
    t.string "city"
    t.string "state"
    t.string "zip"
    t.text "customer_notes"
    t.text "internal_notes"
    t.decimal "subtotal", precision: 10, scale: 2
    t.decimal "taxes", precision: 10, scale: 2
    t.decimal "required_deposit", precision: 10, scale: 2
    t.decimal "total", precision: 10, scale: 2
    t.integer "status"
    t.string "token", null: false
    t.datetime "sent_at"
    t.datetime "viewed_at"
    t.datetime "approved_at"
    t.datetime "declined_at"
    t.datetime "deposit_paid_at"
    t.bigint "booking_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_id"], name: "index_estimates_on_booking_id"
    t.index ["business_id"], name: "index_estimates_on_business_id"
    t.index ["tenant_customer_id"], name: "index_estimates_on_tenant_customer_id"
  end

  create_table "external_calendar_events", force: :cascade do |t|
    t.bigint "calendar_connection_id", null: false
    t.string "external_event_id", null: false
    t.string "external_calendar_id"
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.text "summary"
    t.datetime "last_imported_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_connection_id", "external_event_id"], name: "index_external_calendar_events_on_connection_event_id", unique: true
    t.index ["calendar_connection_id"], name: "index_external_calendar_events_on_calendar_connection_id"
    t.index ["external_event_id"], name: "index_external_calendar_events_on_external_event_id"
    t.index ["last_imported_at"], name: "index_external_calendar_events_on_last_imported_at"
    t.index ["starts_at", "ends_at"], name: "index_external_calendar_events_on_starts_at_and_ends_at"
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
    t.decimal "tip_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "review_request_suppressed", default: false, null: false
    t.index ["booking_id"], name: "index_invoices_on_booking_id"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number"
    t.index ["order_id"], name: "index_invoices_on_order_id"
    t.index ["promotion_id"], name: "index_invoices_on_promotion_id"
    t.index ["shipping_method_id"], name: "index_invoices_on_shipping_method_id"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["tax_rate_id"], name: "index_invoices_on_tax_rate_id"
    t.index ["tenant_customer_id"], name: "index_invoices_on_tenant_customer_id"
    t.index ["tip_amount"], name: "index_invoices_on_tip_amount"
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

  create_table "loyalty_programs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "name", null: false
    t.string "points_name", default: "points", null: false
    t.integer "points_for_booking", default: 0, null: false
    t.integer "points_for_referral", default: 0, null: false
    t.decimal "points_per_dollar", precision: 8, scale: 2, default: "0.0", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_loyalty_programs_on_active"
    t.index ["business_id"], name: "index_loyalty_programs_on_business_id"
  end

  create_table "loyalty_redemptions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.bigint "loyalty_reward_id", null: false
    t.bigint "booking_id"
    t.bigint "order_id"
    t.integer "points_redeemed", null: false
    t.string "status", default: "active", null: false
    t.decimal "discount_amount_applied", precision: 10, scale: 2
    t.string "discount_code", null: false
    t.datetime "created_at", null: false
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
    t.bigint "business_id", null: false
    t.bigint "loyalty_program_id", null: false
    t.string "name", null: false
    t.text "description", null: false
    t.integer "points_required", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_loyalty_rewards_on_active"
    t.index ["business_id"], name: "index_loyalty_rewards_on_business_id"
    t.index ["loyalty_program_id"], name: "index_loyalty_rewards_on_loyalty_program_id"
    t.index ["points_required"], name: "index_loyalty_rewards_on_points_required"
  end

  create_table "loyalty_transactions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.string "transaction_type", null: false
    t.integer "points_amount", null: false
    t.text "description"
    t.datetime "expires_at"
    t.bigint "related_booking_id"
    t.bigint "related_order_id"
    t.bigint "related_referral_id"
    t.datetime "created_at", null: false
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
    t.string "applied_promo_code"
    t.decimal "promo_discount_amount", precision: 10, scale: 2
    t.string "promo_code_type"
    t.decimal "tip_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.boolean "review_request_suppressed", default: false, null: false
    t.index ["applied_promo_code"], name: "index_orders_on_applied_promo_code"
    t.index ["booking_id"], name: "index_orders_on_booking_id"
    t.index ["business_id", "created_at"], name: "index_orders_on_business_id_and_created_at"
    t.index ["business_id"], name: "index_orders_on_business_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["promo_code_type"], name: "index_orders_on_promo_code_type"
    t.index ["shipping_method_id"], name: "index_orders_on_shipping_method_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["tax_rate_id"], name: "index_orders_on_tax_rate_id"
    t.index ["tenant_customer_id", "created_at"], name: "index_orders_on_tenant_customer_id_and_created_at"
    t.index ["tenant_customer_id"], name: "index_orders_on_tenant_customer_id"
    t.index ["tip_amount"], name: "index_orders_on_tip_amount"
    t.check_constraint "status::text = ANY (ARRAY['pending_payment'::character varying::text, 'paid'::character varying::text, 'cancelled'::character varying::text, 'shipped'::character varying::text, 'refunded'::character varying::text, 'processing'::character varying::text, 'business_deleted'::character varying::text])", name: "status_enum_check"
  end

  create_table "page_sections", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.integer "section_type", default: 0
    t.json "content"
    t.integer "position"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "section_config", default: {}
    t.string "custom_css_classes"
    t.string "animation_type"
    t.json "background_settings", default: {}
    t.index ["animation_type"], name: "index_page_sections_on_animation_type"
    t.index ["page_id"], name: "index_page_sections_on_page_id"
  end

  create_table "page_versions", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.bigint "created_by_id"
    t.integer "version_number", null: false
    t.json "content_snapshot", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "published_at", precision: nil
    t.text "change_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_page_versions_on_created_by_id"
    t.index ["page_id", "version_number"], name: "index_page_versions_on_page_id_and_version_number", unique: true
    t.index ["page_id"], name: "index_page_versions_on_page_id"
    t.index ["published_at"], name: "index_page_versions_on_published_at"
    t.index ["status"], name: "index_page_versions_on_status"
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
    t.integer "status", default: 1, null: false
    t.string "template_applied"
    t.json "custom_theme_settings", default: {}
    t.string "seo_title"
    t.text "seo_keywords"
    t.integer "view_count", default: 0, null: false
    t.integer "priority", default: 0, null: false
    t.string "thumbnail_url"
    t.datetime "last_viewed_at"
    t.decimal "performance_score", precision: 5, scale: 2
    t.index ["business_id"], name: "index_pages_on_business_id"
    t.index ["last_viewed_at"], name: "index_pages_on_last_viewed_at"
    t.index ["priority"], name: "index_pages_on_priority"
    t.index ["status"], name: "index_pages_on_status"
    t.index ["template_applied"], name: "index_pages_on_template_applied"
    t.index ["view_count"], name: "index_pages_on_view_count"
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
    t.decimal "tip_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.index ["business_id", "paid_at"], name: "index_payments_on_business_id_and_paid_at"
    t.index ["business_id", "status"], name: "index_payments_on_business_id_and_status"
    t.index ["business_id"], name: "index_payments_on_business_id"
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["stripe_charge_id"], name: "index_payments_on_stripe_charge_id"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
    t.index ["tenant_customer_id"], name: "index_payments_on_tenant_customer_id"
    t.index ["tip_amount"], name: "index_payments_on_tip_amount"
  end

  create_table "platform_discount_codes", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "code", null: false
    t.integer "points_redeemed", null: false
    t.decimal "discount_amount", precision: 10, scale: 2, null: false
    t.string "status", default: "active", null: false
    t.datetime "expires_at"
    t.string "stripe_coupon_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_platform_discount_codes_on_business_id"
    t.index ["code"], name: "index_platform_discount_codes_on_code", unique: true
    t.index ["expires_at"], name: "index_platform_discount_codes_on_expires_at"
    t.index ["status"], name: "index_platform_discount_codes_on_status"
    t.index ["stripe_coupon_id"], name: "index_platform_discount_codes_on_stripe_coupon_id"
  end

  create_table "platform_loyalty_transactions", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "transaction_type", null: false
    t.integer "points_amount", null: false
    t.text "description", null: false
    t.bigint "related_platform_referral_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_platform_loyalty_transactions_on_business_id"
    t.index ["created_at"], name: "index_platform_loyalty_transactions_on_created_at"
    t.index ["related_platform_referral_id"], name: "idx_on_related_platform_referral_id_cfb4a77d6f"
    t.index ["transaction_type"], name: "index_platform_loyalty_transactions_on_transaction_type"
  end

  create_table "platform_referrals", force: :cascade do |t|
    t.bigint "referrer_business_id", null: false
    t.bigint "referred_business_id", null: false
    t.string "referral_code", null: false
    t.string "status", default: "pending", null: false
    t.datetime "qualification_met_at"
    t.datetime "reward_issued_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["referral_code"], name: "index_platform_referrals_on_referral_code", unique: true
    t.index ["referred_business_id"], name: "index_platform_referrals_on_referred_business_id"
    t.index ["referrer_business_id"], name: "index_platform_referrals_on_referrer_business_id"
    t.index ["status"], name: "index_platform_referrals_on_status"
  end

  create_table "policy_acceptances", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "policy_type", null: false
    t.string "policy_version", null: false
    t.datetime "accepted_at", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_at"], name: "index_policy_acceptances_on_accepted_at"
    t.index ["policy_version"], name: "index_policy_acceptances_on_policy_version"
    t.index ["user_id", "policy_type"], name: "index_policy_acceptances_on_user_and_type"
    t.index ["user_id"], name: "index_policy_acceptances_on_user_id"
  end

  create_table "policy_versions", force: :cascade do |t|
    t.string "policy_type", null: false
    t.string "version", null: false
    t.text "content"
    t.string "termly_embed_id"
    t.boolean "active", default: false
    t.boolean "requires_notification", default: false
    t.datetime "effective_date"
    t.text "change_summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["effective_date"], name: "index_policy_versions_on_effective_date"
    t.index ["policy_type", "active"], name: "index_policy_versions_on_policy_type_and_active"
    t.index ["policy_type", "version"], name: "index_policy_versions_on_policy_type_and_version", unique: true
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
    t.bigint "business_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "product_type"
    t.integer "stock_quantity", default: 0, null: false
    t.boolean "tips_enabled", default: false, null: false
    t.boolean "subscription_enabled", default: false, null: false
    t.decimal "subscription_discount_percentage", precision: 5, scale: 2
    t.string "subscription_billing_cycle", default: "monthly"
    t.string "subscription_out_of_stock_action", default: "skip_billing_cycle"
    t.boolean "allow_customer_preferences", default: true, null: false
    t.boolean "allow_discounts", default: true, null: false
    t.boolean "show_stock_to_customers", default: true, null: false
    t.boolean "hide_when_out_of_stock", default: false, null: false
    t.string "variant_label_text", default: "Choose a variant"
    t.integer "position", default: 0
    t.index ["active"], name: "index_products_on_active"
    t.index ["allow_customer_preferences"], name: "index_products_on_allow_customer_preferences"
    t.index ["allow_discounts"], name: "index_products_on_allow_discounts"
    t.index ["business_id", "position"], name: "index_products_on_business_id_and_position"
    t.index ["business_id"], name: "index_products_on_business_id"
    t.index ["featured"], name: "index_products_on_featured"
    t.index ["tips_enabled"], name: "index_products_on_tips_enabled"
  end

  create_table "promotion_products", force: :cascade do |t|
    t.bigint "promotion_id", null: false
    t.bigint "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_promotion_products_on_product_id"
    t.index ["promotion_id", "product_id"], name: "index_promotion_products_on_promotion_id_and_product_id", unique: true
    t.index ["promotion_id"], name: "index_promotion_products_on_promotion_id"
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

  create_table "promotion_services", force: :cascade do |t|
    t.bigint "promotion_id", null: false
    t.bigint "service_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["promotion_id", "service_id"], name: "index_promotion_services_on_promotion_id_and_service_id", unique: true
    t.index ["promotion_id"], name: "index_promotion_services_on_promotion_id"
    t.index ["service_id"], name: "index_promotion_services_on_service_id"
  end

  create_table "promotions", force: :cascade do |t|
    t.string "name", null: false
    t.string "code"
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
    t.boolean "applicable_to_products", default: true, null: false
    t.boolean "applicable_to_services", default: true, null: false
    t.boolean "public_dates", default: false, null: false
    t.boolean "allow_discount_codes", default: true, null: false
    t.index ["applicable_to_products"], name: "index_promotions_on_applicable_to_products"
    t.index ["applicable_to_services"], name: "index_promotions_on_applicable_to_services"
    t.index ["business_id"], name: "index_promotions_on_business_id"
    t.index ["code", "business_id"], name: "index_promotions_on_code_and_business_id", unique: true, where: "(code IS NOT NULL)"
    t.index ["public_dates"], name: "index_promotions_on_public_dates"
  end

  create_table "referral_programs", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.boolean "active", default: true, null: false
    t.string "referrer_reward_type", default: "points", null: false
    t.decimal "referrer_reward_value", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "referral_code_discount_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "min_purchase_amount", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_referral_programs_on_active"
    t.index ["business_id"], name: "index_referral_programs_on_business_id"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "referrer_id", null: false
    t.string "referral_code", null: false
    t.string "status", default: "pending", null: false
    t.datetime "reward_issued_at"
    t.datetime "qualification_met_at"
    t.bigint "qualifying_booking_id"
    t.bigint "qualifying_order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "referred_tenant_customer_id"
    t.index ["business_id", "referral_code"], name: "index_referrals_on_business_id_and_referral_code", unique: true
    t.index ["business_id"], name: "index_referrals_on_business_id"
    t.index ["qualifying_booking_id"], name: "index_referrals_on_qualifying_booking_id"
    t.index ["qualifying_order_id"], name: "index_referrals_on_qualifying_order_id"
    t.index ["referral_code"], name: "index_referrals_on_referral_code"
    t.index ["referred_tenant_customer_id"], name: "index_referrals_on_referred_tenant_customer_id"
    t.index ["referrer_id"], name: "index_referrals_on_referrer_id"
    t.index ["status"], name: "index_referrals_on_status"
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

  create_table "service_variants", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.string "name", null: false
    t.integer "duration", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.boolean "active", default: true
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_id", "name"], name: "index_service_variants_on_service_id_and_name", unique: true
    t.index ["service_id"], name: "index_service_variants_on_service_id"
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
    t.boolean "tips_enabled", default: false, null: false
    t.boolean "subscription_enabled", default: false, null: false
    t.decimal "subscription_discount_percentage", precision: 5, scale: 2
    t.string "subscription_billing_cycle", default: "monthly"
    t.string "subscription_rebooking_preference", default: "same_day_next_month"
    t.boolean "allow_customer_preferences", default: true, null: false
    t.boolean "allow_discounts", default: true, null: false
    t.integer "position", default: 0
    t.jsonb "availability", default: {}, null: false
    t.boolean "enforce_service_availability", default: true, null: false
    t.index ["allow_customer_preferences"], name: "index_services_on_allow_customer_preferences"
    t.index ["allow_discounts"], name: "index_services_on_allow_discounts"
    t.index ["business_id", "position"], name: "index_services_on_business_id_and_position"
    t.index ["business_id"], name: "index_services_on_business_id"
    t.index ["name", "business_id"], name: "index_services_on_name_and_business_id", unique: true
    t.index ["tips_enabled"], name: "index_services_on_tips_enabled"
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

  create_table "setup_reminder_dismissals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "task_key", null: false
    t.datetime "dismissed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "task_key"], name: "index_setup_reminder_dismissals_on_user_id_and_task_key", unique: true
    t.index ["user_id"], name: "index_setup_reminder_dismissals_on_user_id"
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
    t.bigint "default_calendar_connection_id"
    t.index ["business_id"], name: "index_staff_members_on_business_id"
    t.index ["default_calendar_connection_id"], name: "index_staff_members_on_default_calendar_connection_id"
    t.index ["user_id"], name: "index_staff_members_on_user_id"
  end

  create_table "stock_movements", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.integer "quantity"
    t.string "movement_type"
    t.string "reference_id"
    t.string "reference_type"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_stock_movements_on_product_id"
  end

  create_table "stock_reservations", force: :cascade do |t|
    t.bigint "product_variant_id"
    t.bigint "order_id"
    t.integer "quantity"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "subscription_transactions", force: :cascade do |t|
    t.bigint "customer_subscription_id", null: false
    t.bigint "business_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.bigint "order_id"
    t.bigint "booking_id"
    t.bigint "invoice_id"
    t.bigint "payment_id"
    t.string "transaction_type", null: false
    t.integer "status", default: 0, null: false
    t.date "processed_date", null: false
    t.decimal "amount", precision: 10, scale: 2
    t.text "failure_reason"
    t.integer "retry_count", default: 0
    t.datetime "next_retry_at"
    t.integer "loyalty_points_awarded", default: 0
    t.jsonb "metadata"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_invoice_id"
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
    t.bigint "user_id"
    t.boolean "email_marketing_opt_out"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "unsubscribe_token"
    t.datetime "unsubscribed_at"
    t.index ["business_id"], name: "index_tenant_customers_on_business_id"
    t.index ["email", "business_id"], name: "index_tenant_customers_on_email_and_business_id", unique: true
    t.index ["stripe_customer_id"], name: "index_tenant_customers_on_stripe_customer_id", unique: true
    t.index ["unsubscribe_token"], name: "index_tenant_customers_on_unsubscribe_token", unique: true
    t.index ["user_id"], name: "index_tenant_customers_on_user_id"
  end

  create_table "test_models", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tip_configurations", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.json "default_tip_percentages", default: [15, 18, 20], null: false
    t.boolean "custom_tip_enabled", default: true, null: false
    t.text "tip_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_tip_configurations_on_business_id"
  end

  create_table "tips", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.bigint "booking_id", null: false
    t.bigint "tenant_customer_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "stripe_payment_intent_id"
    t.string "stripe_charge_id"
    t.string "stripe_customer_id"
    t.integer "status", default: 0, null: false
    t.datetime "paid_at"
    t.text "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "stripe_fee_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "platform_fee_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.decimal "business_amount", precision: 10, scale: 2, null: false
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
    t.bigint "user_id", null: false
    t.string "item_key", null: false
    t.integer "position", default: 0, null: false
    t.boolean "visible", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "item_key"], name: "index_user_sidebar_items_on_user_id_and_item_key", unique: true
    t.index ["user_id"], name: "index_user_sidebar_items_on_user_id"
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
    t.boolean "requires_policy_acceptance", default: false
    t.datetime "last_policy_notification_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "referral_source_code"
    t.boolean "email_marketing_opt_out"
    t.string "unsubscribe_token"
    t.datetime "unsubscribed_at"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["current_sign_in_at"], name: "index_users_on_current_sign_in_at"
    t.index ["email", "role"], name: "index_users_on_email_and_role"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_sign_in_at"], name: "index_users_on_last_sign_in_at"
    t.index ["requires_policy_acceptance"], name: "index_users_on_requires_policy_acceptance"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unsubscribe_token"], name: "index_users_on_unsubscribe_token", unique: true
  end

  create_table "website_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "industry", null: false
    t.integer "template_type", default: 0, null: false
    t.json "structure", default: {}, null: false
    t.json "default_theme", default: {}, null: false
    t.text "preview_image_url"
    t.text "description"
    t.boolean "requires_premium", default: false, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "requires_premium"], name: "index_website_templates_on_active_and_requires_premium"
    t.index ["industry"], name: "index_website_templates_on_industry"
    t.index ["template_type"], name: "index_website_templates_on_template_type"
  end

  create_table "website_themes", force: :cascade do |t|
    t.bigint "business_id", null: false
    t.string "name", null: false
    t.json "color_scheme", default: {}, null: false
    t.json "typography", default: {}, null: false
    t.json "layout_config", default: {}, null: false
    t.text "custom_css"
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id", "active"], name: "index_website_themes_on_business_id_and_active"
    t.index ["business_id"], name: "index_website_themes_on_business_id"
    t.index ["name"], name: "index_website_themes_on_name"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
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
  add_foreign_key "estimate_items", "estimates"
  add_foreign_key "estimate_items", "services"
  add_foreign_key "estimates", "bookings"
  add_foreign_key "estimates", "businesses"
  add_foreign_key "estimates", "tenant_customers"
  add_foreign_key "external_calendar_events", "calendar_connections"
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
  add_foreign_key "platform_discount_codes", "businesses", on_delete: :cascade
  add_foreign_key "platform_loyalty_transactions", "businesses", on_delete: :cascade
  add_foreign_key "platform_loyalty_transactions", "platform_referrals", column: "related_platform_referral_id"
  add_foreign_key "platform_referrals", "businesses", column: "referred_business_id", on_delete: :cascade
  add_foreign_key "platform_referrals", "businesses", column: "referrer_business_id", on_delete: :cascade
  add_foreign_key "policy_acceptances", "users"
  add_foreign_key "product_variants", "products"
  add_foreign_key "products", "businesses", on_delete: :cascade
  add_foreign_key "promotion_products", "products", on_delete: :cascade
  add_foreign_key "promotion_products", "promotions", on_delete: :cascade
  add_foreign_key "promotion_redemptions", "bookings", on_delete: :cascade
  add_foreign_key "promotion_redemptions", "invoices"
  add_foreign_key "promotion_redemptions", "promotions"
  add_foreign_key "promotion_redemptions", "tenant_customers"
  add_foreign_key "promotion_services", "promotions", on_delete: :cascade
  add_foreign_key "promotion_services", "services", on_delete: :cascade
  add_foreign_key "promotions", "businesses", on_delete: :cascade
  add_foreign_key "referral_programs", "businesses", on_delete: :cascade
  add_foreign_key "referrals", "bookings", column: "qualifying_booking_id"
  add_foreign_key "referrals", "businesses", on_delete: :cascade
  add_foreign_key "referrals", "orders", column: "qualifying_order_id"
  add_foreign_key "referrals", "tenant_customers", column: "referred_tenant_customer_id"
  add_foreign_key "referrals", "users", column: "referrer_id"
  add_foreign_key "service_variants", "services"
  add_foreign_key "services", "businesses", on_delete: :cascade
  add_foreign_key "services_staff_members", "services", on_delete: :cascade
  add_foreign_key "services_staff_members", "staff_members", on_delete: :cascade
  add_foreign_key "setup_reminder_dismissals", "users"
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
  add_foreign_key "subscriptions", "businesses", on_delete: :cascade
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
  add_foreign_key "website_themes", "businesses"
end
