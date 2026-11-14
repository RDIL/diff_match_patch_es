# frozen_string_literal: true

require_relative 'test_helper'

# noinspection RbsMissingTypeSignature
class JsStringTest < Minitest::Test
  JS = DMP::JsString

  def test_substring
    assert_equal 'bc', JS.substring('abc', 1)
    assert_equal '', JS.substring('abc', 3)
    assert_equal '', JS.substring('abc', 5)
    assert_equal 'ab', JS.substring('abc', -1, 2)
    assert_equal 'b', JS.substring('abc', 2, 1) # The arguments swap.
    assert_equal 'bc', JS.substring('abc', 3, 1)
    assert_equal 'bc', JS.substring('abc', 1, 10)
    assert_equal '', JS.substring('abc', 4, 9)
    assert_equal 'b', JS.substring('abc', 1, 2)
    assert_equal '', JS.substring('abc', 1, 1)
    assert_equal '本語', JS.substring('日本語', 1)
    assert_equal '本', JS.substring('日本語', 1, 2)

    # Indices past the character count but within the byte count.
    assert_equal '語', JS.substring('日本語', 2, 7)
    assert_equal '', JS.substring('日本語', 3, 8)
    assert_equal '', JS.substring('日本語', 5)
    assert_equal '本語', JS.substring('日本語', 5, 1)

    # Indices too large for a machine word.
    assert_equal 'bc', JS.substring('abc', 1, 2**70)
    assert_equal 'abc', JS.substring('abc', 2**70, -(2**70))

    # An invalid byte counts as one character.
    invalid = "a\xFFbc".dup.force_encoding(Encoding::UTF_8)
    assert_equal "\xFFb".b, JS.substring(invalid, 1, 3).b

    # The result keeps the encoding, even when empty, and is a new string.
    sjis = '日本語'.encode(Encoding::Shift_JIS)
    assert_equal '本'.encode(Encoding::Shift_JIS), JS.substring(sjis, 1, 2)
    assert_equal Encoding::Shift_JIS, JS.substring(sjis, 3).encoding
    assert_equal Encoding::Shift_JIS, JS.substring(sjis, 7, 9).encoding
    refute_predicate JS.substring('abc', 0), :frozen?
    refute_predicate JS.substring('abc', 3), :frozen?
  end

  def test_index_of
    assert_equal 1, JS.index_of('abcabc', 'bc')
    assert_equal 4, JS.index_of('abcabc', 'bc', 2)
    assert_equal(-1, JS.index_of('abcabc', 'bc', 5))
    assert_equal 0, JS.index_of('abc', 'a', -5)
    assert_equal(-1, JS.index_of('abc', 'c', 10))
    assert_equal 1, JS.index_of('日本語', '本')
    assert_equal 2, JS.index_of('日本語日本語', '語', 1)
    assert_equal 5, JS.index_of('日本語日本語', '語', 3)
    assert_equal(-1, JS.index_of('日本語', '日', 1))
    assert_equal(-1, JS.index_of('日本語', '語', 5))

    # An empty pattern matches at min(from, length).
    assert_equal 0, JS.index_of('abc', '')
    assert_equal 1, JS.index_of('abc', '', 1)
    assert_equal 3, JS.index_of('abc', '', 10)
    assert_equal 3, JS.index_of('日本語', '', 3)
    assert_equal 3, JS.index_of('日本語', '', 5)

    # Offsets too large for a machine word.
    assert_equal 3, JS.index_of('abc', '', 2**70)
    assert_equal(-1, JS.index_of('abc', 'c', 2**70))
    assert_equal 2, JS.index_of('abc', 'c', -(2**70))

    # An invalid byte counts as one character.
    invalid = "日\xFF本語本".dup.force_encoding(Encoding::UTF_8)
    assert_equal 4, JS.index_of(invalid, '本', 3)

    # A match starts on a character boundary: the second byte of "ソ" is a backslash.
    sjis = "aソ\\".encode(Encoding::Shift_JIS)
    assert_equal 2, JS.index_of(sjis, '\\'.encode(Encoding::Shift_JIS), 1)

    # A pattern in another, compatible encoding.
    assert_equal 4, JS.index_of('日本語abc', 'b'.encode(Encoding::US_ASCII), 2)

    # Incompatible encodings raise wherever the search starts.
    utf16 = '本'.encode(Encoding::UTF_16LE)
    [0, 1, 3, 5, 20].each do |from|
      assert_raises(Encoding::CompatibilityError, from.to_s) { JS.index_of('日本語', utf16, from) }
    end
  end

  def test_last_index_of
    assert_equal 3, JS.last_index_of('abcabc', 'abc', 100)
    assert_equal 3, JS.last_index_of('abcabc', 'abc', 3)
    assert_equal 0, JS.last_index_of('abcabc', 'abc', 2)
    assert_equal 0, JS.last_index_of('abc', 'a', -1)
    assert_equal(-1, JS.last_index_of('abc', 'b', -1))
    assert_equal(-1, JS.last_index_of('abc', 'd', 3))
    assert_equal 4, JS.last_index_of('日本語日本語', '本', 4)
    assert_equal 1, JS.last_index_of('日本語日本語', '本', 3)
    assert_equal(-1, JS.last_index_of('日本語日本語', '本', 0))
    assert_equal 3, JS.last_index_of('日本語日本語', '日本語', 9)

    # An empty pattern matches at min(from, length).
    assert_equal 3, JS.last_index_of('abc', '', 100)
    assert_equal 2, JS.last_index_of('日本語', '', 2)
    assert_equal 3, JS.last_index_of('日本語', '', 7)

    # Offsets too large for a machine word.
    assert_equal 2, JS.last_index_of('日本語', '語', 2**70)
    assert_equal 0, JS.last_index_of('日本語', '日', -(2**70))
    assert_equal(-1, JS.last_index_of('日本語', '語', -(2**70)))

    # A pattern with more bytes than the text has left at the search start.
    assert_equal(-1, JS.last_index_of('a' * 55, '😀' * 4, 55))
    assert_equal 2, JS.last_index_of('aa😀😀a', '😀😀', 5)

    # An invalid byte counts as one character.
    invalid = "日\xFF本語本".dup.force_encoding(Encoding::UTF_8)
    assert_equal 2, JS.last_index_of(invalid, '本', 3)
    assert_equal 4, JS.last_index_of(invalid, '本', 9)

    # A match starts on a character boundary: the second byte of "ソ" is a backslash.
    sjis = "\\ソa".encode(Encoding::Shift_JIS)
    assert_equal 0, JS.last_index_of(sjis, '\\'.encode(Encoding::Shift_JIS), 2)

    # A pattern in another, compatible encoding.
    assert_equal 4, JS.last_index_of('日本語abc', 'b'.encode(Encoding::US_ASCII), 5)

    # Incompatible encodings raise wherever the search starts.
    utf16 = '本'.encode(Encoding::UTF_16LE)
    [0, 1, 3, 5, 20].each do |from|
      assert_raises(Encoding::CompatibilityError, from.to_s) { JS.last_index_of('日本語', utf16, from) }
    end
  end

  def test_encode_uri
    assert_equal "AZaz09;,/?:@&=+$-_.!~*'()#", JS.encode_uri("AZaz09;,/?:@&=+$-_.!~*'()#")
    assert_equal '%C3%A9%F0%9F%98%80%20/', JS.encode_uri('é😀 /')
    assert_equal '%22%3C%3E%5B%5D%7B%7D%7C%5C%5E%60%25', JS.encode_uri('"<>[]{}|\\^`%')
    assert_equal '%0A%09%00%7F', JS.encode_uri("\n\t\x00\x7F")
    assert_equal 'a%20b%20%20c%2520', JS.encode_uri('a b  c%20')
    assert_equal '', JS.encode_uri('')

    # The result is a new UTF-8 string, whatever the encoding of the text.
    latin = JS.encode_uri('café'.encode(Encoding::ISO_8859_1))
    assert_equal 'caf%E9', latin
    assert_equal Encoding::UTF_8, latin.encoding
    assert_equal Encoding::UTF_8, JS.encode_uri('abc'.b).encoding
    refute_predicate JS.encode_uri('abc'), :frozen?

    # Every byte of an escaped character is escaped: the second byte of "ソ" is a backslash.
    assert_equal '%83%5C', JS.encode_uri('ソ'.encode(Encoding::Shift_JIS))

    # Invalid text and ASCII-incompatible encodings raise.
    assert_raises(ArgumentError) { JS.encode_uri("a\xFF".dup.force_encoding(Encoding::UTF_8)) }
    assert_raises(Encoding::CompatibilityError) { JS.encode_uri('a'.encode(Encoding::UTF_16LE)) }
  end

  def test_decode_uri
    assert_equal 'A', JS.decode_uri('%41')
    assert_equal 'é', JS.decode_uri('%c3%a9')
    assert_equal '€', JS.decode_uri('%E2%82%AC')
    assert_equal '😀', JS.decode_uri('%F0%9F%98%80')
    assert_equal 'é😀 /', JS.decode_uri(JS.encode_uri('é😀 /'))
    assert_equal "line one\nline two\t100%", JS.decode_uri('line one%0Aline two%09100%25')
    assert_equal '日本語 text 日本語', JS.decode_uri('日本語 text %E6%97%A5%E6%9C%AC%E8%AA%9E')

    # Escapes of reserved characters are kept verbatim, including their case.
    assert_equal '%2f', JS.decode_uri('%2f')
    assert_equal 'A%2FB', JS.decode_uri('%41%2F%42')
    assert_equal 'a%23b', JS.decode_uri('a%23b')
    assert_equal 'path%2Fto%3fx%3D1 é', JS.decode_uri('path%2Fto%3fx%3D1%20%C3%A9')

    # A decoded '%' never starts a new escape.
    assert_equal '%41', JS.decode_uri('%2541')
    assert_equal 'long text %C3%A9', JS.decode_uri('long text %25C3%25A9')

    # Malformed: lone or truncated escapes, non-hex digits, overlong forms,
    # surrogates, code points above U+10FFFF, and incomplete sequences.
    %w[% %4 %4G %41% %C0%80 %ED%A0%80 %F4%90%80%80 %E2%82 %E2%82x %C3%2F %80 %ff].each do |bad|
      assert_raises(JS::UriError, bad) { JS.decode_uri(bad) }
      assert_raises(JS::UriError, bad) { JS.decode_uri("some longer text #{bad}") }
    end

    # The result is a new UTF-8 string, whatever the encoding of the text.
    ascii = JS.decode_uri('plain %41SCII and %c3%a9'.encode(Encoding::US_ASCII))
    assert_equal 'plain ASCII and é', ascii
    assert_equal Encoding::UTF_8, ascii.encoding
    assert_equal Encoding::UTF_8, JS.decode_uri('plain text'.b).encoding
    assert_equal Encoding::UTF_8, JS.decode_uri(''.encode(Encoding::UTF_16LE)).encoding
    refute_predicate JS.decode_uri('plain text'), :frozen?

    # Invalid bytes pass through.
    invalid = "\xFF%41 text".dup.force_encoding(Encoding::UTF_8)
    assert_equal "\xFFA text".b, JS.decode_uri(invalid).b
  end
end
