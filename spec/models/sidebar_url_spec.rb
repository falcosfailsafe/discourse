# frozen_string_literal: true

RSpec.describe SidebarUrl do
  it "validates external URLs" do
    expect(
      SidebarUrl.new(
        icon: "link",
        name: "external",
        value: "https://www.test.com/discourse-test",
      ).valid?,
    ).to eq(true)
    expect(
      SidebarUrl.new(
        icon: "link",
        name: "categories",
        value: "http://#{Discourse.current_hostname}/pub/test",
      ).valid?,
    ).to eq(true)
    expect(
      SidebarUrl.new(
        icon: "link",
        name: "external",
        value: "https://www.test.com/" + "a" * 979,
      ).valid?,
    ).to eq(true)
    expect(
      SidebarUrl.new(
        icon: "link",
        name: "external",
        value: "https://www.test.com/" + "a" * 980,
      ).valid?,
    ).to eq(false)
  end

  it "sets external flag" do
    expect(
      SidebarUrl.create!(icon: "link", name: "categories", value: "/categories").external,
    ).to be false
    expect(
      SidebarUrl.create!(
        icon: "link",
        name: "categories",
        value: "http://#{Discourse.current_hostname}/categories",
      ).external,
    ).to be false
    expect(
      SidebarUrl.create!(
        icon: "link",
        name: "categories",
        value: "https://#{Discourse.current_hostname}/categories",
      ).external,
    ).to be false
    expect(
      SidebarUrl.create!(
        icon: "link",
        name: "categories",
        value: "https://www.test.com/discourse-test",
      ).external,
    ).to be true
  end

  describe ".built_in_community_section_link_value?" do
    it "matches built-in relative and current-host absolute URLs while rejecting external hosts" do
      expect(SidebarUrl.built_in_community_section_link_value?("/latest")).to eq(true)
      expect(
        SidebarUrl.built_in_community_section_link_value?(
          "https://#{Discourse.current_hostname}/latest",
        ),
      ).to eq(true)
      expect(
        SidebarUrl.built_in_community_section_link_value?(
          "http://#{Discourse.current_hostname}/my/messages",
        ),
      ).to eq(true)
      expect(
        SidebarUrl.built_in_community_section_link_value?(
          "https://#{Discourse.current_hostname}.evil.example/latest",
        ),
      ).to eq(false)
      expect(SidebarUrl.built_in_community_section_link_value?("https://example.com/latest")).to eq(
        false,
      )
      expect(SidebarUrl.built_in_community_section_link_value?("/custom-page")).to eq(false)
    end
  end
end
