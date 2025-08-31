# frozen_string_literal: true

# Dynamically allow custom domains stored in the businesses table to pass
# Rails’ Host Authorization middleware in production. This prevents 403
# “Blocked hosts” errors when a tenant’s custom domain is first connected.
#
# • Runs only in production – development & test already configure hosts
#   explicitly in their respective environment files.
# • Wrap DB queries in robust error handling so boot won’t fail in cases
#   where the database is unavailable (e.g. during assets:precompile).
# • We intentionally do NOT wildcard-allow every host; only domains that
#   exist in the database (plus their `www.` aliases) are permitted.
#
# NOTE: This uses runtime data, not static Rails configuration files,
#       keeping with the project’s preference for env-based config while
#       preserving security best practices.

return unless Rails.env.production?

begin
  # Ensure Business model is loaded and DB schema is present before querying.
  if defined?(Business) && Business.respond_to?(:where) && Business.table_exists?
    Business.where(host_type: "custom_domain").where.not(hostname: [nil, ""]).pluck(:hostname).each do |domain|
      Rails.application.config.hosts << domain
      Rails.application.config.hosts << "www.#{domain}" unless domain.start_with?("www.")
    end
  else
    Rails.logger.info("[CustomDomainHosts] Business model not available during boot; skipping host preload")
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, PG::UndefinedTable, StandardError => e
  Rails.logger.warn("[CustomDomainHosts] Skipping dynamic host loading: #{e.class} – #{e.message}")
end
