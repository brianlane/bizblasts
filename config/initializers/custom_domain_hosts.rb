# frozen_string_literal: true

# Dynamically allow custom domains stored in the businesses table to pass
# Rails’ Host Authorization middleware in production. This prevents 403
# “Blocked hosts” errors when a tenant’s custom domain is connected.

return unless Rails.env.production?

# Helper to add hosts idempotently
add_hosts = lambda do |domains|
  next if domains.blank?
  # Build normalized set to avoid duplicates
  existing = Rails.application.config.hosts.dup
  Array(domains).map(&:to_s).each do |domain|
    root = domain.sub(/^www\./, '')
    [domain, root, "www.#{root}"].uniq.each do |h|
      Rails.application.config.hosts << h unless existing.include?(h)
      existing << h
    end
  end
end

# During asset builds or early boot, the DB/model may not be available.
# Keep the lightweight guard for those phases.
begin
  if defined?(Business) && Business.respond_to?(:where) && Business.table_exists?
    domains = Business.where(host_type: "custom_domain").where.not(hostname: [nil, ""]).pluck(:hostname)
    add_hosts.call(domains)
  else
    Rails.logger.info("[CustomDomainHosts] Business model not available during early boot; scheduling after_initialize load")
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, PG::UndefinedTable, StandardError => e
  Rails.logger.warn("[CustomDomainHosts] Skipping early host preload: #{e.class} – #{e.message}")
end

# Ensure hosts are added once the app is fully initialized (runtime boots).
Rails.application.config.after_initialize do
  begin
    model = 'Business'.safe_constantize
    unless model && model.respond_to?(:where)
      Rails.logger.info('[CustomDomainHosts] Business model unavailable after_initialize; skipping')
      next
    end

    if ActiveRecord::Base.connection.data_source_exists?('businesses')
      domains = model.where(host_type: 'custom_domain')
                     .where.not(hostname: [nil, ''])
                     .pluck(:hostname)
      add_hosts.call(domains)
      Rails.logger.info("[CustomDomainHosts] Hosts list size: #{Rails.application.config.hosts.size}")
    end
  rescue => e
    Rails.logger.warn("[CustomDomainHosts] after_initialize load failed: #{e.class} – #{e.message}")
  end
end
