# frozen_string_literal: true

module DiffMatchPatchES
  # Helpers that reproduce JavaScript string semantics exactly.
  module JsString
    module_function

    # JS String.prototype.substring: negative/overflowing indices clamp to [0, length] and the arguments swap when start > end.
    def substring(str, start_index, end_index = nil)
      # Common case first: String#[] clamps the end itself, so String#length
      # (a scan of multi-byte text) is only needed for the odd cases below.
      size = str.bytesize
      if start_index.between?(0, size)
        count = end_index.nil? || end_index >= size ? size : end_index - start_index
        result = str[start_index, count] if count >= 0
        return result if result
      end

      len = str.length
      a = start_index.clamp(0, len)
      b = end_index.nil? ? len : end_index.clamp(0, len)
      a, b = b, a if a > b
      str[a...b]
    end

    # JS String.prototype.charAt: '' when out of range.
    def char_at(str, index)
      return '' if index.negative? || index >= str.length

      str[index]
    end

    # JS String.prototype.indexOf.
    def index_of(str, pattern, from = 0)
      # String#index counts the characters of +str+ to validate an offset,
      # so a search from the start passes none.
      return str.index(pattern) || -1 unless from.positive?

      # It also walks multi-byte text to the offset one character at a time.
      # Slicing off the tail is much faster, and the slice shares the text.
      if !str.ascii_only? && str.encoding == pattern.encoding && from <= str.bytesize &&
         (tail = str[from, str.bytesize])
        found = tail.index(pattern)
        return found ? found + from : -1
      end

      from = from.clamp(0, str.length)
      str.index(pattern, from) || -1
    end

    # JS String.prototype.lastIndexOf: the match may start at or before +from+.
    def last_index_of(str, pattern, from)
      # String#rindex can read past the end of the text
      # (https://bugs.ruby-lang.org/issues/22548), and it walks multi-byte text
      # to its start one character at a time. Search by byte where that is exact.
      # In ASCII-only text a character offset is a byte offset.
      return str.byterindex(pattern, from.clamp(0, str.bytesize)) || -1 if str.ascii_only?

      if str.encoding == Encoding::UTF_8 && pattern.encoding == Encoding::UTF_8 && str.valid_encoding?
        size = str.bytesize
        from = from.clamp(0, size)
        tail = str[from, size] # nil when +from+ is past the last character.
        limit = tail ? size - tail.bytesize : size
        found = str.byterindex(pattern, limit)
        return -1 unless found

        # Turn the byte offset into a character index by counting the
        # characters on the shorter side of the match.
        return str.byteslice(0, found).length if found < limit - found

        return (tail ? from : str.length) - str.byteslice(found, limit - found).length
      end

      from = from.clamp(0, str.length)
      str.rindex(pattern, from) || -1
    end

    # JS Number.parseInt(str, 10): optional leading whitespace and sign,
    # JS StrWhiteSpace: ASCII whitespace, NBSP, BOM, and Unicode space separators.
    JS_PARSE_INT = /\A[\t\n\v\f\r \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]*([+-]?\d+)/

    # then as many digits as possible. Returns nil where JS returns NaN.
    def parse_int(str)
      match = JS_PARSE_INT.match(str)
      match && match[1].to_i
    end

    # Characters encodeURI leaves unescaped.
    ENCODE_URI_UNESCAPED = /\A[A-Za-z0-9;,\/?:@&=+$\-_.!~*'()#]\z/
    # Runs of characters encodeURI escapes, other than the space.
    ENCODE_URI_ESCAPED = /[^A-Za-z0-9;,\/?:@&=+$\-_.!~*'()# ]+/
    # The %XX escape of each byte value.
    BYTE_ESCAPES = (0..255).map { |byte| format('%%%02X', byte).freeze }.freeze
    # Characters whose escape sequences decodeURI refuses to decode
    # (uriReserved plus '#').
    DECODE_URI_RESERVED = ";/?:@&=+$,#"
    # Runs of escaped bytes outside ASCII, which decode together as UTF-8.
    DECODE_URI_WIDE = /(?:%[89A-Fa-f]\h)+/
    # A '%' that does not begin the escape of an ASCII byte.
    DECODE_URI_MALFORMED = /%(?![0-7]\h)/
    # The escape of an ASCII byte, and what each one decodes to: its character,
    # or the escape itself when the character is reserved.
    DECODE_URI_ASCII = /%[0-7]\h/
    DECODE_URI_ASCII_ESCAPES = [*'0'..'7'].product([*'0'..'9', *'A'..'F', *'a'..'f']).to_h do |digits|
      escape = "%#{digits.join}".freeze
      char = digits.join.hex.chr.freeze
      [escape, DECODE_URI_RESERVED.include?(char) ? escape : char]
    end.freeze

    # JS encodeURI: percent-encodes the UTF-8 bytes of every character outside
    # the unescaped set, using uppercase hex.
    def encode_uri(str)
      # Texts of a few bytes are quicker through the loop below.
      if str.bytesize > 5 && str.valid_encoding? && str.encoding.ascii_compatible?
        # One gsub keeps the scan in C. Spaces, the most common escape, go last
        # through a plain-string gsub, which costs far less per match.
        escaped = str.gsub(ENCODE_URI_ESCAPED) do |run|
          next BYTE_ESCAPES[run.getbyte(0)] if run.bytesize == 1

          hex = +''
          run.each_byte { |byte| hex << BYTE_ESCAPES[byte] }
          hex
        end
        escaped.gsub!(' ', '%20')
        return escaped.force_encoding(Encoding::UTF_8)
      end

      out = +''
      str.each_char do |ch|
        if ENCODE_URI_UNESCAPED.match?(ch)
          out << ch
        else
          ch.each_byte { |b| out << format('%%%02X', b) }
        end
      end
      out
    end

    class UriError < StandardError; end

    # JS decodeURI: decodes %XX escape sequences as strict UTF-8 (rejecting
    # malformed, overlong, surrogate, and out-of-range sequences) while leaving
    # escapes of reserved characters (";/?:@&=+$,#") untouched.
    def decode_uri(str)
      # Texts of a few bytes are quicker through the loop below.
      if str.bytesize > 6 && (str.encoding == Encoding::UTF_8 ? str.valid_encoding? : str.ascii_only?)
        # Multi-byte characters first: decoding them cannot produce a '%' for
        # the next pass to misread, where decoding %25 can. Ruby's UTF-8
        # validity rules are decodeURI's.
        decoded = str.gsub(DECODE_URI_WIDE) do |run|
          chars = [run.delete('%')].pack('H*').force_encoding(Encoding::UTF_8)
          raise UriError, 'URI malformed' unless chars.valid_encoding?

          chars
        end
        raise UriError, 'URI malformed' if decoded.match?(DECODE_URI_MALFORMED)

        return decoded.gsub(DECODE_URI_ASCII, DECODE_URI_ASCII_ESCAPES).force_encoding(Encoding::UTF_8)
      end

      out = +''
      i = 0
      n = str.length
      while i < n
        ch = str[i]
        unless ch == '%'
          out << ch
          i += 1
          next
        end
        start = i
        b0 = read_escaped_byte(str, i)
        i += 3
        if b0 < 0x80
          decoded = b0.chr
          if DECODE_URI_RESERVED.include?(decoded)
            out << str[start, 3]
          else
            out << decoded
          end
        else
          extra =
            case b0
            when 0xC2..0xDF then 1
            when 0xE0..0xEF then 2
            when 0xF0..0xF4 then 3
            else raise UriError, 'URI malformed'
            end
          codepoint = b0 & (0x3F >> extra)
          extra.times do
            raise UriError, 'URI malformed' unless str[i] == '%'

            byte = read_escaped_byte(str, i)
            raise UriError, 'URI malformed' unless (byte & 0xC0) == 0x80

            codepoint = (codepoint << 6) | (byte & 0x3F)
            i += 3
          end
          minimum = [0x80, 0x800, 0x10000][extra - 1]
          if codepoint < minimum || codepoint > 0x10FFFF || (0xD800..0xDFFF).cover?(codepoint)
            raise UriError, 'URI malformed'
          end

          out << codepoint.chr(Encoding::UTF_8)
        end
      end
      out
    end

    def read_escaped_byte(str, index)
      hex = str[index + 1, 2]
      raise UriError, 'URI malformed' unless hex&.length == 2 && /\A\h\h\z/.match?(hex)

      hex.to_i(16)
    end
  end
end
