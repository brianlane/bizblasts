# frozen_string_literal: true

require 'rails_helper'

# Admin panel smoke test.
#
# Renders the index page of EVERY registered ActiveAdmin resource and page.
# This catches the class of production-only 500s we have been bitten by:
#   - a filter referencing an attribute missing from ransackable_attributes
#     (NoMethodError on Ransack::Search while rendering the filter sidebar)
#   - an ActiveAdmin `scope` that doesn't exist on the model
#   - index columns/status_tags that crash once at least one record exists
#
# A few records are seeded so data-dependent rendering paths are exercised.
RSpec.describe 'Admin panel smoke test', type: :request, admin: true do
  before do
    ActsAsTenant.without_tenant do
      business = create(:business)
      create(:document_template, business: business)
      create(:payment)
      subscription = create(:customer_subscription)
      create(:subscription_transaction, customer_subscription: subscription)
    end
  end

  it 'renders every registered admin index page without a server error' do
    namespace = ActiveAdmin.application.namespaces[:admin]
    failures = []
    visited = 0

    namespace.resources.each do |resource|
      path = begin
        resource.route_collection_path
      rescue StandardError
        # Some entries (e.g. belongs_to-nested resources) have no standalone
        # collection route; skip them.
        nil
      end
      next unless path

      visited += 1

      begin
        get path
      rescue StandardError => e
        failures << "#{path}: raised #{e.class}: #{e.message.lines.first&.strip}"
        next
      end

      failures << "#{path}: returned #{response.status}" if response.status >= 500
    end

    expect(visited).to be > 0
    expect(failures).to be_empty, "Admin pages failed:\n#{failures.join("\n")}"
  end
end
