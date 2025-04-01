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

ActiveRecord::Schema[8.0].define(version: 2025_04_02_000000) do
  create_schema "default"
  create_schema "tenant1"
  create_schema "tenant2"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "appointments", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "service_id", null: false
    t.bigint "service_provider_id", null: false
    t.string "client_name", null: false
    t.string "client_email"
    t.string "client_phone"
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.string "status", default: "scheduled"
    t.decimal "price", precision: 10, scale: 2
    t.text "notes"
    t.jsonb "metadata", default: {}
    t.string "stripe_payment_intent_id"
    t.string "stripe_customer_id"
    t.boolean "paid", default: false
    t.datetime "cancelled_at"
    t.text "cancellation_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "start_time"], name: "index_appointments_on_company_id_and_start_time"
    t.index ["company_id"], name: "index_appointments_on_company_id"
    t.index ["paid"], name: "index_appointments_on_paid"
    t.index ["service_id"], name: "index_appointments_on_service_id"
    t.index ["service_provider_id"], name: "index_appointments_on_service_provider_id"
    t.index ["status"], name: "index_appointments_on_status"
  end

  create_table "business_hours", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.integer "day_of_week", null: false
    t.time "open_time"
    t.time "close_time"
    t.boolean "is_closed", default: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "day_of_week"], name: "index_business_hours_on_company_id_and_day_of_week", unique: true
    t.index ["company_id"], name: "index_business_hours_on_company_id"
  end

  create_table "client_websites", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "service_template_id", null: false
    t.string "name", null: false
    t.string "subdomain"
    t.string "domain"
    t.boolean "active", default: true
    t.jsonb "content", default: {}
    t.jsonb "settings", default: {}
    t.jsonb "theme", default: {}
    t.string "status", default: "draft"
    t.datetime "published_at"
    t.boolean "custom_domain_enabled", default: false
    t.boolean "ssl_enabled", default: false
    t.jsonb "seo_settings", default: {}
    t.jsonb "analytics", default: {}
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_client_websites_on_active"
    t.index ["company_id", "subdomain"], name: "index_client_websites_on_company_id_and_subdomain", unique: true
    t.index ["company_id"], name: "index_client_websites_on_company_id"
    t.index ["domain"], name: "index_client_websites_on_domain", unique: true
    t.index ["service_template_id"], name: "index_client_websites_on_service_template_id"
    t.index ["status"], name: "index_client_websites_on_status"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name"
    t.string "subdomain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "service_providers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.boolean "active", default: true
    t.jsonb "availability", default: {}
    t.jsonb "settings", default: {}
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_providers_on_active"
    t.index ["company_id", "name"], name: "index_service_providers_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_service_providers_on_company_id"
  end

  create_table "service_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "category"
    t.string "industry"
    t.boolean "active", default: true
    t.jsonb "features", default: []
    t.jsonb "pricing", default: {}
    t.jsonb "content", default: {}
    t.jsonb "settings", default: {}
    t.string "status", default: "draft"
    t.datetime "published_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_service_templates_on_active"
    t.index ["category"], name: "index_service_templates_on_category"
    t.index ["industry"], name: "index_service_templates_on_industry"
    t.index ["status"], name: "index_service_templates_on_status"
  end

  create_table "services", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.string "name", null: false
    t.text "description"
    t.decimal "price", precision: 10, scale: 2
    t.integer "duration_minutes"
    t.boolean "active", default: true
    t.jsonb "settings", default: {}
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_services_on_active"
    t.index ["company_id", "name"], name: "index_services_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_services_on_company_id"
  end

  create_table "software_products", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "version"
    t.string "category"
    t.boolean "active", default: true
    t.jsonb "features", default: []
    t.jsonb "pricing", default: {}
    t.string "license_type"
    t.text "setup_instructions"
    t.string "documentation_url"
    t.string "support_url"
    t.boolean "requires_installation", default: false
    t.boolean "is_saas", default: true
    t.string "status", default: "draft"
    t.datetime "published_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_software_products_on_active"
    t.index ["category"], name: "index_software_products_on_category"
    t.index ["status"], name: "index_software_products_on_status"
  end

  create_table "software_subscriptions", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "software_product_id", null: false
    t.string "status", default: "active"
    t.datetime "started_at"
    t.datetime "ends_at"
    t.string "license_key"
    t.string "subscription_type"
    t.jsonb "subscription_details", default: {}
    t.boolean "auto_renew", default: true
    t.string "payment_status"
    t.string "stripe_subscription_id"
    t.string "stripe_customer_id"
    t.jsonb "usage_metrics", default: {}
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "software_product_id"], name: "idx_on_company_id_software_product_id_3a351575da", unique: true
    t.index ["company_id"], name: "index_software_subscriptions_on_company_id"
    t.index ["license_key"], name: "index_software_subscriptions_on_license_key", unique: true
    t.index ["software_product_id"], name: "index_software_subscriptions_on_software_product_id"
    t.index ["status"], name: "index_software_subscriptions_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "company_id", null: false
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "appointments", "companies"
  add_foreign_key "appointments", "service_providers"
  add_foreign_key "appointments", "services"
  add_foreign_key "business_hours", "companies"
  add_foreign_key "client_websites", "companies"
  add_foreign_key "client_websites", "service_templates"
  add_foreign_key "service_providers", "companies"
  add_foreign_key "services", "companies"
  add_foreign_key "software_subscriptions", "companies"
  add_foreign_key "software_subscriptions", "software_products"
  add_foreign_key "users", "companies"
end
