# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneNormalizer do
  describe ".normalize" do
    it "returns nil for nil input" do
      expect(described_class.normalize(nil)).to be_nil
    end

    it "returns blank string for blank input to avoid overwriting existing blanks" do
      expect(described_class.normalize("")).to eq("")
    end

    it "normalizes 10 digit numbers to include the default country code" do
      expect(described_class.normalize("206-555-7890")).to eq("+12065557890")
    end

    it "preserves short numbers by prefixing a plus sign" do
      expect(described_class.normalize("123")).to eq("+123")
    end
  end

  describe ".normalize_collection" do
    it "normalizes each value and keeps blanks intact" do
      result = described_class.normalize_collection(["123", "", nil, "123"])

      expect(result).to eq(["+123", ""])
    end
  end
end
