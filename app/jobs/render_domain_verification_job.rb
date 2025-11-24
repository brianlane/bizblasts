# frozen_string_literal: true

# Background job to trigger Render domain verification asynchronously.
# This avoids inline sleeps and duplicate API calls during setup/monitoring.
class RenderDomainVerificationJob < ApplicationJob
  queue_as :default

  # Retry a few times in case Render is temporarily inconsistent
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Perform verification for the given domain name. The job will look up the
  # domain in Render and, if present and not yet verified, call the verify API.
  # @param domain_name [String]
  def perform(domain_name)
    Rails.logger.info "[RenderDomainVerificationJob] Verifying domain by name: #{domain_name}"

    service = RenderDomainService.new

    domain = service.find_domain_by_name(domain_name)
    if domain.nil?
      Rails.logger.info "[RenderDomainVerificationJob] Domain not found in Render: #{domain_name}"
      return
    end

    domain_data = service.normalize_domain_data(domain)
    if domain_data['verificationStatus'] == 'verified' || domain_data['verified'] == true
      Rails.logger.info "[RenderDomainVerificationJob] Domain already verified: #{domain_name}"
      return
    end

    begin
      result = service.verify_domain(domain_data['id'])
      Rails.logger.info "[RenderDomainVerificationJob] Verify result for #{domain_name}: verified=#{result['verified']}, queued=#{result['queued']}"
    rescue => e
      Rails.logger.warn "[RenderDomainVerificationJob] Verification failed for #{domain_name}: #{e.message}"
      raise e
    end
  end
end


