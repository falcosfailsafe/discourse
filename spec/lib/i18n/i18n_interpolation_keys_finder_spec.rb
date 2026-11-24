# frozen_string_literal: true

RSpec.describe I18nInterpolationKeysFinder do
  describe "#find" do
    it "returns the interpolation keys" do
      expect(described_class.find("%{first} %{second} {{third}} %{first}")).to eq(
        %w[first second third],
      )
    end

    it "returns an empty array for plain strings or non-strings" do
      expect(described_class.find("Plain translation text without placeholders")).to eq([])
      expect(described_class.find("100% complete")).to eq([])
      expect(described_class.find(nil)).to eq([])
    end

    it "respects custom I18n.config.interpolation_patterns" do
      original = I18n.config.interpolation_patterns
      I18n.config.interpolation_patterns = [*original, /\[\[([a-z_]+)\]\]/]

      expect(described_class.find("Hello [[user_name]] and {{site_name}}")).to eq(
        %w[user_name site_name],
      )
    ensure
      I18n.config.interpolation_patterns = original
    end
  end
end
