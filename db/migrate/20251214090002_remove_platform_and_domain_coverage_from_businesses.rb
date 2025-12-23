# frozen_string_literal: true

class RemovePlatformAndDomainCoverageFromBusinesses < ActiveRecord::Migration[7.1]
  def change
    # Remove indexes first (safe no-ops if already absent).
    remove_index :businesses, :platform_referral_code, if_exists: true
    remove_index :businesses, :domain_coverage_applied, if_exists: true
    remove_index :businesses, :domain_coverage_expires_at, if_exists: true
    remove_index :businesses, :domain_renewal_date, if_exists: true
    remove_index :businesses, :domain_auto_renewal_enabled, if_exists: true

    # Remove BizBlasts platform referral/loyalty columns.
    remove_column :businesses, :platform_loyalty_points, :integer, if_exists: true
    remove_column :businesses, :platform_referral_code, :string, if_exists: true

    # Remove deprecated domain coverage columns (BizBlasts no longer offers domain coverage).
    remove_column :businesses, :domain_auto_renewal_enabled, :boolean, if_exists: true
    remove_column :businesses, :domain_cost_covered, :decimal, if_exists: true
    remove_column :businesses, :domain_coverage_applied, :boolean, if_exists: true
    remove_column :businesses, :domain_coverage_expires_at, :date, if_exists: true
    remove_column :businesses, :domain_coverage_notes, :text, if_exists: true
    remove_column :businesses, :domain_registrar, :string, if_exists: true
    remove_column :businesses, :domain_registration_date, :date, if_exists: true
    remove_column :businesses, :domain_renewal_date, :date, if_exists: true
  end
end

