# frozen_string_literal: true

class I18nInterpolationKeysFinder
  CUSTOM_INTERPOLATION_PATTERN = /\{\{(\w+)\}\}/
  DEFAULT_PATTERN =
    Regexp.union([*I18n::DEFAULT_INTERPOLATION_PATTERNS, CUSTOM_INTERPOLATION_PATTERN])
  CUSTOM_PATTERNS_CACHE = LruRedux::ThreadSafeCache.new(8)
  private_constant :CUSTOM_INTERPOLATION_PATTERN, :DEFAULT_PATTERN, :CUSTOM_PATTERNS_CACHE

  def self.find(text)
    return [] unless text.is_a?(String)

    patterns = I18n.config.interpolation_patterns
    if patterns == I18n::DEFAULT_INTERPOLATION_PATTERNS
      return [] if !text.include?("%") && !text.include?("{{")
      pattern = DEFAULT_PATTERN
    else
      key = patterns.frozen? ? patterns : patterns.dup.freeze
      pattern =
        CUSTOM_PATTERNS_CACHE.getset(key) { Regexp.union([*key, CUSTOM_INTERPOLATION_PATTERN]) }
    end

    keys = text.scan(pattern)
    return [] if keys.empty?

    keys.flatten!
    keys.compact!
    keys.uniq!
    keys
  end
end
