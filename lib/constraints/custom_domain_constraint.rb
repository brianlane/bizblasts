# frozen_string_literal: true

# Routes constraint that returns true when the incoming Host header
# belongs to an active custom-domain tenant.
class CustomDomainConstraint
  def self.matches?(request)
    host = request.host.to_s.downcase
    root = host.sub(/^www\./, '')
    candidates = [host, root, "www.#{root}"].uniq

    begin
      return false unless defined?(Business)
      return false unless ActiveRecord::Base.connection.data_source_exists?('businesses')

      Business.where(host_type: 'custom_domain', status: 'cname_active')
              .where('LOWER(hostname) IN (?)', candidates)
              .exists?
    rescue StandardError => e
      Rails.logger.warn "[CustomDomainConstraint] Error while matching host=#{host}: #{e.class} #{e.message}"
      false
    end
  end
end
