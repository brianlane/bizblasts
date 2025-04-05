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

ActiveRecord::Schema[8.0].define(version: 2025_04_05_164806) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.string "subdomain", null: false
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
    t.index ["name"], name: "index_businesses_on_name"
    t.index ["subdomain"], name: "index_businesses_on_subdomain", unique: true
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
    t.index ["booking_id"], name: "index_invoices_on_booking_id"
    t.index ["business_id"], name: "index_invoices_on_business_id"
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number"
    t.index ["promotion_id"], name: "index_invoices_on_promotion_id"
    t.index ["status"], name: "index_invoices_on_status"
    t.index ["tenant_customer_id"], name: "index_invoices_on_tenant_customer_id"
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
    t.string "category"
    t.string "industry"
    t.boolean "active", default: true
    t.string "status", default: "draft"
    t.jsonb "features"
    t.jsonb "pricing"
    t.jsonb "content"
    t.jsonb "settings"
    t.datetime "published_at"
    t.jsonb "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_templates_on_active"
    t.index ["category"], name: "index_service_templates_on_category"
    t.index ["industry"], name: "index_service_templates_on_industry"
    t.index ["name"], name: "index_service_templates_on_name"
    t.index ["status"], name: "index_service_templates_on_status"
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
    t.integer "role", default: 0
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "business_id"
    t.bigint "staff_member_id"
    t.index ["business_id", "email"], name: "index_users_on_business_id_and_email", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "bookings", "businesses"
  add_foreign_key "bookings", "promotions"
  add_foreign_key "bookings", "services"
  add_foreign_key "bookings", "staff_members"
  add_foreign_key "bookings", "tenant_customers"
  add_foreign_key "campaign_recipients", "marketing_campaigns"
  add_foreign_key "campaign_recipients", "tenant_customers"
  add_foreign_key "invoices", "bookings"
  add_foreign_key "invoices", "businesses"
  add_foreign_key "invoices", "promotions"
  add_foreign_key "invoices", "tenant_customers"
  add_foreign_key "marketing_campaigns", "businesses"
  add_foreign_key "marketing_campaigns", "promotions"
  add_foreign_key "promotion_redemptions", "bookings"
  add_foreign_key "promotion_redemptions", "invoices"
  add_foreign_key "promotion_redemptions", "promotions"
  add_foreign_key "promotion_redemptions", "tenant_customers"
  add_foreign_key "promotions", "businesses"
  add_foreign_key "services", "businesses"
  add_foreign_key "services_staff_members", "services"
  add_foreign_key "services_staff_members", "staff_members"
  add_foreign_key "sms_messages", "bookings"
  add_foreign_key "sms_messages", "marketing_campaigns"
  add_foreign_key "sms_messages", "tenant_customers"
  add_foreign_key "staff_members", "businesses"
  add_foreign_key "staff_members", "users"
  add_foreign_key "tenant_customers", "businesses"
  add_foreign_key "users", "businesses"
  add_foreign_key "users", "staff_members"
end
