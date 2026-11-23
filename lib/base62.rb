# frozen_string_literal: true

# Modified version of: https://github.com/steventen/base62-rb

module Base62
  KEYS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  KEYS_HASH = KEYS.each_char.with_index.to_h
  BASE = KEYS.length
  CHUNK_SIZE = 9
  CHUNK_BASE = BASE**CHUNK_SIZE
  POWERS = (0..CHUNK_SIZE).map { |exp| BASE**exp }.freeze
  DECODE_MAP =
    Array
      .new(128) do |byte|
        if byte >= 48 && byte <= 57
          byte - 48
        elsif byte >= 97 && byte <= 122
          byte - 87
        elsif byte >= 65 && byte <= 90
          byte - 29
        end
      end
      .freeze
  private_constant :CHUNK_SIZE, :CHUNK_BASE, :POWERS, :DECODE_MAP

  # Encodes base10 (decimal) number to base62 string.
  def self.encode(num)
    return "0" if num == 0
    return nil if num < 0

    bytes = []
    while num >= CHUNK_BASE
      num, rem = num.divmod(CHUNK_BASE)
      i = 0
      while i < CHUNK_SIZE
        rem, digit = rem.divmod(BASE)
        bytes << KEYS.getbyte(digit)
        i += 1
      end
    end

    while num > 0
      num, digit = num.divmod(BASE)
      bytes << KEYS.getbyte(digit)
    end

    bytes.reverse!
    bytes.pack("C*").force_encoding(Encoding::UTF_8)
  end

  # Decodes base62 string to a base10 (decimal) number.
  def self.decode(str)
    return fallback_decode(str) if !str.encoding.ascii_compatible?

    len = str.bytesize
    num = 0
    i = 0

    while len - i >= CHUNK_SIZE
      chunk = 0
      stop = i + CHUNK_SIZE
      while i < stop
        byte = str.getbyte(i)
        val = byte < 128 ? DECODE_MAP[byte] : nil
        return fallback_decode(str) if val.nil?
        chunk = (chunk * BASE) + val
        i += 1
      end
      num = (num * CHUNK_BASE) + chunk
    end

    if i < len
      rem_len = len - i
      chunk = 0
      while i < len
        byte = str.getbyte(i)
        val = byte < 128 ? DECODE_MAP[byte] : nil
        return fallback_decode(str) if val.nil?
        chunk = (chunk * BASE) + val
        i += 1
      end
      num = (num * POWERS[rem_len]) + chunk
    end

    num
  end

  def self.fallback_decode(str)
    num = 0
    i = 0
    len = str.length - 1
    while i < str.length
      pow = BASE**(len - i)
      num += KEYS_HASH[str[i]] * pow
      i += 1
    end
    num
  end
  private_class_method :fallback_decode
end
