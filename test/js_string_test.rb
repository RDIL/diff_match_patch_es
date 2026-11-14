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
end
