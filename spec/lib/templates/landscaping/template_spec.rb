require 'rails_helper'

RSpec.describe Templates::Landscaping::Template do
  describe '.default_template' do
    it 'returns a hash representing the landscaping template structure' do
      template = described_class.default_template
      expect(template).to be_a(Hash)
      expect(template[:name]).to eq("Landscaping Business Template")
      expect(template[:sections]).to be_an(Array)
      expect(template[:sections]).to include("header", "services", "contact")
      expect(template[:color_scheme]).to eq("green")
      expect(template[:layout]).to eq("nature")
    end
  end

  describe '.available_components' do
    it 'returns an array of available landscaping component names' do
      components = described_class.available_components
      expect(components).to be_an(Array)
      expect(components).to include("header", "footer", "services", "projects")
      expect(components.length).to be > 5 # Check for a reasonable number
    end
  end
end 