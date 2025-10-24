# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhoneNormalizer do
  describe ".normalize" do
    it "returns nil for nil input" do
      expect(described_class.normalize(nil)).to be_nil
    end

    it "returns nil for blank input to prevent persisting invalid data" do
      expect(described_class.normalize("")).to be_nil
      expect(described_class.normalize("   ")).to be_nil
    end

    it "normalizes 10 digit numbers to include the default country code" do
      expect(described_class.normalize("206-555-7890")).to eq("+12065557890")
    end

    it "returns nil for short numbers (< 7 digits) to prevent invalid data" do
      expect(described_class.normalize("123")).to be_nil
      expect(described_class.normalize("12345")).to be_nil
    end

    it "normalizes valid 7+ digit numbers" do
      expect(described_class.normalize("1234567")).to eq("+1234567")
      expect(described_class.normalize("12345678901")).to eq("+12345678901")
    end

    it "returns nil for non-digit inputs to prevent invalid data" do
      expect(described_class.normalize("--")).to be_nil
      expect(described_class.normalize("abc")).to be_nil
    end
  end

  describe ".normalize_collection" do
    it "normalizes each value and filters out invalid/blank entries" do
      result = described_class.normalize_collection(["2065557890", "", nil, "2065557890", "123"])

      expect(result).to eq(["+12065557890"])
    end

    it "handles arrays with only invalid values" do
      result = described_class.normalize_collection(["", nil, "123", "--"])

      expect(result).to eq([])
    end
  end
end
