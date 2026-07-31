# frozen_string_literal: true

module DiffMatchPatchES
  # Helpers that reproduce JavaScript string semantics exactly.
  module JsString
    module_function

    # JS String.prototype.substring: negative/overflowing indices clamp to [0, length] and the arguments swap when start > end.
    def substring(str, start_index, end_index = nil)
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
      from = from.clamp(0, str.length)
      str.index(pattern, from) || -1
    end

    # JS String.prototype.lastIndexOf: the match may start at or before +from+.
    def last_index_of(str, pattern, from)
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
    # Characters whose escape sequences decodeURI refuses to decode
    # (uriReserved plus '#').
    DECODE_URI_RESERVED = ";/?:@&=+$,#"

    # JS encodeURI: percent-encodes the UTF-8 bytes of every character outside
    # the unescaped set, using uppercase hex.
    def encode_uri(str)
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
