#!/usr/bin/env ruby
# frozen_string_literal: true

require "openssl"
require "base64"

# Minimal CloudFront signed URL generator (canned policy).
#
# Why:
# - Our app generates CloudFront URLs like https://<distribution>/<active_storage_key>
# - If the distribution requires signed URLs (common when S3 bucket is private),
#   unsigned URLs will return 403 and the client-side cropper can't load the image.
#
# Env vars supported:
# - CLOUDFRONT_KEY_PAIR_ID: CloudFront key pair ID
# - CLOUDFRONT_PRIVATE_KEY_PEM: PEM string (can include newlines)
# - CLOUDFRONT_PRIVATE_KEY_BASE64: base64-encoded PEM (handy for env storage)
# - CLOUDFRONT_PRIVATE_KEY_PATH: absolute path to PEM file
# - CLOUDFRONT_URL_TTL_SECONDS: optional, default 1 hour
#
module CloudfrontUrlSigner
  module_function

  def configured?
    key_pair_id != "" && private_key_pem != ""
  end

  def signed_url(url, expires_at: default_expires_at)
    return url unless configured?

    expires = expires_at.to_i
    policy = canned_policy(url, expires)
    signature = url_safe_base64(rsa_sign(policy))

    delimiter = url.include?("?") ? "&" : "?"
    "#{url}#{delimiter}Expires=#{expires}&Signature=#{signature}&Key-Pair-Id=#{key_pair_id}"
  end

  def default_expires_at
    raw = ENV["CLOUDFRONT_URL_TTL_SECONDS"].to_s.strip
    ttl = (raw == "" ? 3600 : raw.to_i)
    Time.now.utc + ttl
  end

  def canned_policy(resource_url, expires_epoch)
    %({"Statement":[{"Resource":"#{resource_url}","Condition":{"DateLessThan":{"AWS:EpochTime":#{expires_epoch}}}}]})
  end

  def rsa_sign(message)
    rsa = OpenSSL::PKey::RSA.new(private_key_pem)
    rsa.sign(OpenSSL::Digest::SHA1.new, message)
  end

  # CloudFront uses a URL-safe base64 variant:
  # + => -
  # = => _
  # / => ~
  def url_safe_base64(bytes)
    Base64.strict_encode64(bytes).tr("+/=", "-~_")
  end

  def key_pair_id
    ENV["CLOUDFRONT_KEY_PAIR_ID"].to_s.strip
  end

  def private_key_pem
    @private_key_pem ||= begin
      if (pem = ENV["CLOUDFRONT_PRIVATE_KEY_PEM"].to_s).strip != ""
        pem
      elsif (b64 = ENV["CLOUDFRONT_PRIVATE_KEY_BASE64"].to_s).strip != ""
        Base64.decode64(b64)
      elsif (path = ENV["CLOUDFRONT_PRIVATE_KEY_PATH"].to_s).strip != ""
        File.read(path)
      else
        ""
      end
    end
  end
end



