# frozen_string_literal: true

class TextSentinel
  attr_accessor :text

  ENTROPY_SCALE = 0.7
  MAX_WORD_LENGTH_REGEXPS = {}
  MAX_WORD_LENGTH_MUTEX = Mutex.new
  private_constant :MAX_WORD_LENGTH_REGEXPS, :MAX_WORD_LENGTH_MUTEX

  def initialize(text, opts = nil)
    @opts = opts || {}
    str = text.to_s
    @text =
      if str.encoding == Encoding::UTF_8 && str.valid_encoding?
        str
      else
        str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
      end
  end

  def self.body_sentinel(text, opts = {})
    entropy = SiteSetting.body_min_entropy
    if opts[:private_message]
      scale_entropy =
        SiteSetting.min_personal_message_post_length.to_f / SiteSetting.min_post_length.to_f
      entropy = (entropy * scale_entropy).to_i
      entropy =
        (SiteSetting.min_personal_message_post_length.to_f * ENTROPY_SCALE).to_i if entropy >
        SiteSetting.min_personal_message_post_length
    else
      entropy = (SiteSetting.min_post_length.to_f * ENTROPY_SCALE).to_i if entropy >
        SiteSetting.min_post_length
    end
    TextSentinel.new(text, min_entropy: entropy)
  end

  def self.title_sentinel(text, min_length: SiteSetting.min_topic_title_length)
    entropy =
      if min_length > SiteSetting.title_min_entropy
        SiteSetting.title_min_entropy
      else
        (min_length.to_f * ENTROPY_SCALE).to_i
      end
    TextSentinel.new(text, min_entropy: entropy, max_word_length: SiteSetting.title_max_word_length)
  end

  # Number of unique bytes
  def entropy
    @entropy ||=
      begin
        stripped = @text.strip
        # Five 52-bit masks cover all 256 byte values inside 63-bit signed Fixnums without Bignum promotion.
        mask0 = 0
        mask1 = 0
        mask2 = 0
        mask3 = 0
        mask4 = 0
        count = 0
        i = 0
        len = stripped.bytesize

        while i < len
          byte = stripped.getbyte(i)
          if byte < 52
            bit = 1 << byte
            if (mask0 & bit) == 0
              mask0 |= bit
              count += 1
            end
          elsif byte < 104
            bit = 1 << (byte - 52)
            if (mask1 & bit) == 0
              mask1 |= bit
              count += 1
            end
          elsif byte < 156
            bit = 1 << (byte - 104)
            if (mask2 & bit) == 0
              mask2 |= bit
              count += 1
            end
          elsif byte < 208
            bit = 1 << (byte - 156)
            if (mask3 & bit) == 0
              mask3 |= bit
              count += 1
            end
          else
            bit = 1 << (byte - 208)
            if (mask4 & bit) == 0
              mask4 |= bit
              count += 1
            end
          end
          i += 1
        end

        count
      end
  end

  def valid?
    @text.present? && seems_meaningful? && seems_pronounceable? && seems_unpretentious? &&
      seems_quiet?
  end

  # Ensure minimum entropy
  def seems_meaningful?
    @opts[:min_entropy].nil? || entropy >= @opts[:min_entropy]
  end

  # At least one non-symbol character
  def seems_pronounceable?
    @text.match?(/\p{Alnum}/)
  end

  # Ensure maximum word length
  def seems_unpretentious?
    skipped_locales.include?(SiteSetting.default_locale) || @opts[:max_word_length].nil? ||
      !@text.match?(max_word_length_regexp(@opts[:max_word_length] + 1))
  end

  # Ensure at least one lowercase letter
  def seems_quiet?
    SiteSetting.allow_uppercase_posts || @text.match?(/\p{Lowercase_Letter}|\p{Other_Letter}/) ||
      !@text.match?(/\p{Letter}/)
  end

  private

  def max_word_length_regexp(min_run)
    MAX_WORD_LENGTH_REGEXPS[min_run] ||
      MAX_WORD_LENGTH_MUTEX.synchronize do
        MAX_WORD_LENGTH_REGEXPS[min_run] ||= /\p{Alnum}{#{min_run},}/
      end
  end

  # Hard to tell "word length" for CJK languages
  def skipped_locales
    @skipped_locales ||= %w[ja ko zh_CN zh_TW].freeze
  end
end
