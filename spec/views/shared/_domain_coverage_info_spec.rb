# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "shared/_domain_coverage_info", type: :view do
  describe "domain coverage information partial" do
    before do
      render partial: "shared/domain_coverage_info"
    end

    it "displays the domain coverage title" do
      expect(rendered).to have_content("Custom Domain Coverage")
      expect(rendered).to include("🌐")
    end

    it "shows new domain registration coverage" do
      expect(rendered).to have_content("New Domain Registration:")
      expect(rendered).to have_content("BizBlasts covers up to $20/year")
    end

    it "shows existing domain policy" do
      expect(rendered).to have_content("Existing Domain:")
      expect(rendered).to have_content("You handle domain costs")
    end

    it "shows over $20/year policy" do
      expect(rendered).to have_content("Over $20/year:")
      expect(rendered).to have_content("We'll suggest alternatives")
    end

    it "shows included services" do
      expect(rendered).to have_content("Domain verification, technical setup, SSL certificates, and DNS management")
    end

    it "uses appropriate CSS classes for styling" do
      expect(rendered).to include("bg-light")
      expect(rendered).to include("border-success")
      expect(rendered).to include("border-warning")
      expect(rendered).to include("border-info")
    end

    it "has proper semantic structure" do
      expect(rendered).to have_css("div.bg-light")
      expect(rendered).to have_css("h4", text: "Custom Domain Coverage")
      expect(rendered).to have_css("div.space-y-3")
    end
  end
end 