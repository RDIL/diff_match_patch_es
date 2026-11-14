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
end
