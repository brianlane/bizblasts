# frozen_string_literal: true

class AddAnalyticsConstraintsAndIndexes < ActiveRecord::Migration[8.0]
  def up
    # Add functional index on LOWER(first_referrer_domain) for traffic source queries
    # This improves performance when querying traffic sources with case-insensitive matching
    execute <<-SQL
      CREATE INDEX IF NOT EXISTS index_visitor_sessions_on_lower_first_referrer_domain
      ON visitor_sessions (LOWER(first_referrer_domain))
      WHERE first_referrer_domain IS NOT NULL;
    SQL

    # Add CHECK constraint for visitor_fingerprint format validation
    # Fingerprint should be a hexadecimal string between 8-32 characters
    # This is generated client-side as a hash of browser characteristics
    execute <<-SQL
      ALTER TABLE visitor_sessions
      ADD CONSTRAINT visitor_fingerprint_format_check
      CHECK (
        visitor_fingerprint IS NULL OR
        (
          LENGTH(visitor_fingerprint) BETWEEN 8 AND 32 AND
          visitor_fingerprint ~ '^[a-f0-9]+$'
        )
      );
    SQL

    # Also add constraint to page_views table for visitor_fingerprint consistency
    execute <<-SQL
      ALTER TABLE page_views
      ADD CONSTRAINT page_views_visitor_fingerprint_format_check
      CHECK (
        visitor_fingerprint IS NULL OR
        (
          LENGTH(visitor_fingerprint) BETWEEN 8 AND 32 AND
          visitor_fingerprint ~ '^[a-f0-9]+$'
        )
      );
    SQL

    # Also add constraint to click_events table for visitor_fingerprint consistency
    execute <<-SQL
      ALTER TABLE click_events
      ADD CONSTRAINT click_events_visitor_fingerprint_format_check
      CHECK (
        visitor_fingerprint IS NULL OR
        (
          LENGTH(visitor_fingerprint) BETWEEN 8 AND 32 AND
          visitor_fingerprint ~ '^[a-f0-9]+$'
        )
      );
    SQL
  end

  def down
    # Remove CHECK constraints
    execute <<-SQL
      ALTER TABLE click_events
      DROP CONSTRAINT IF EXISTS click_events_visitor_fingerprint_format_check;
    SQL

    execute <<-SQL
      ALTER TABLE page_views
      DROP CONSTRAINT IF EXISTS page_views_visitor_fingerprint_format_check;
    SQL

    execute <<-SQL
      ALTER TABLE visitor_sessions
      DROP CONSTRAINT IF EXISTS visitor_fingerprint_format_check;
    SQL

    # Remove functional index
    execute <<-SQL
      DROP INDEX IF EXISTS index_visitor_sessions_on_lower_first_referrer_domain;
    SQL
  end
end
