# frozen_string_literal: true

describe Chat::SlackCompatibility do
  describe "#process_text" do
    it "converts mrkdwn links to regular markdown" do
      text = described_class.process_text("this is some text <https://discourse.org>")
      expect(text).to eq("this is some text https://discourse.org")
    end

    it "converts mrkdwn links with titles to regular markdown" do
      text =
        described_class.process_text("this is some text <https://discourse.org|Discourse Forums>")
      expect(text).to eq("this is some text [Discourse Forums](https://discourse.org)")
    end

    it "handles multiple links" do
      text =
        described_class.process_text(
          "this is some text <https://discourse.org|Discourse Forums> with a second link to <https://discourse.org/team>",
        )
      expect(text).to eq(
        "this is some text [Discourse Forums](https://discourse.org) with a second link to https://discourse.org/team",
      )
    end

    it "converts <!here> and <!all> to our mention format" do
      text = described_class.process_text("<!here> this is some important stuff <!all>")
      expect(text).to eq("@here this is some important stuff @all")
    end

    it "preserves plain messages and handles pipe edge cases and UTF-8 titles" do
      plain = "deployment succeeded on prod-1 without any mrkdwn links"
      result = described_class.process_text(plain)
      expect(result).to eq(plain)
      expect(result).not_to equal(plain)

      expect(described_class.process_text("<||>")).to eq("")
      expect(described_class.process_text("<https://example.com|>")).to eq("https://example.com")
      expect(described_class.process_text("<|label>")).to eq("[label]()")
      expect(described_class.process_text("<https://example.com|a|b>")).to eq(
        "[a](https://example.com)",
      )
      expect(described_class.process_text("<https://discourse.org|日本語フォーラム 🚀>")).to eq(
        "[日本語フォーラム 🚀](https://discourse.org)",
      )
    end
  end
end
