require 'rails_helper'

RSpec.describe BusinessManager::ServicesHelper, type: :helper do
  describe "#format_service_duration" do
    it "formats minutes into hours and minutes when over an hour" do
      expect(helper.format_service_duration(90)).to eq("1h 30m")
    end

    it "formats minutes only when under an hour" do
      expect(helper.format_service_duration(45)).to eq("45m")
    end
  end

  describe "#service_status_tag" do
    let(:active_service) { build_stubbed(:service, active: true) }
    let(:inactive_service) { build_stubbed(:service, active: false) }

    it "returns an active status tag for active services" do
      expect(helper.service_status_tag(active_service)).to include('Active')
      expect(helper.service_status_tag(active_service)).to include('bg-green-100')
    end

    it "returns an inactive status tag for inactive services" do
      expect(helper.service_status_tag(inactive_service)).to include('Inactive')
      expect(helper.service_status_tag(inactive_service)).to include('bg-red-100')
    end
  end
end
