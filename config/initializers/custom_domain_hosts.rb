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
  # Fetch custom-domain hostnames (pluck avoids loading entire records).
  Business.where(host_type: "custom_domain").where.not(hostname: [nil, ""]).pluck(:hostname).each do |domain|
    Rails.application.config.hosts << domain
    # Add the www alias if the domain itself is not already prefixed.
    Rails.application.config.hosts << "www.#{domain}" unless domain.start_with?("www.")
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, PG::UndefinedTable => e
  Rails.logger.warn("[CustomDomainHosts] Skipping dynamic host loading: #{e.class} – #{e.message}")
end
