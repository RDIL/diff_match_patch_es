# frozen_string_literal: true

require_relative 'test_helper'

class MatchTest < Minitest::Test
  def test_match_alphabet
    # Initialise the bitmasks for Bitap.
    # Unique.
    assert_equal({ 'a' => 4, 'b' => 2, 'c' => 1 }, DMP.match_alphabet('abc'))

    # Duplicates.
    assert_equal({ 'a' => 37, 'b' => 18, 'c' => 8 }, DMP.match_alphabet('abcaba'))
  end

  def test_match_bitap
    options = DMP.resolve_options(match_distance: 100, match_max_bits: 32)

    # Bitap algorithm.
    # Exact matches.
    assert_equal 5, DMP.match_bitap('abcdefghijk', 'fgh', 5, options)

    assert_equal 5, DMP.match_bitap('abcdefghijk', 'fgh', 0, options)

    # Fuzzy matches.
    assert_equal 4, DMP.match_bitap('abcdefghijk', 'efxhi', 0, options)

    assert_equal 2, DMP.match_bitap('abcdefghijk', 'cdefxyhijk', 5, options)

    assert_equal(-1, DMP.match_bitap('abcdefghijk', 'bxy', 1, options))

    # Overflow.
    assert_equal 2, DMP.match_bitap('123456789xx0', '3456789x0', 2, options)

    # Threshold test.
    options.match_threshold = 0.4
    assert_equal 4, DMP.match_bitap('abcdefghijk', 'efxyhi', 1, options)

    options.match_threshold = 0.3
    assert_equal(-1, DMP.match_bitap('abcdefghijk', 'efxyhi', 1, options))

    options.match_threshold = 0.0
    assert_equal 1, DMP.match_bitap('abcdefghijk', 'bcdef', 1, options)

    options.match_threshold = 0.5

    # Multiple select.
    assert_equal 0, DMP.match_bitap('abcdexyzabcde', 'abccde', 3, options)

    assert_equal 8, DMP.match_bitap('abcdexyzabcde', 'abccde', 5, options)

    # Distance test.
    options.match_distance = 10 # Strict location.
    assert_equal(-1, DMP.match_bitap('abcdefghijklmnopqrstuvwxyz', 'abcdefg', 24, options))

    assert_equal 0, DMP.match_bitap('abcdefghijklmnopqrstuvwxyz', 'abcdxxefg', 1, options)

    options.match_distance = 1000 # Loose location.
    assert_equal 0, DMP.match_bitap('abcdefghijklmnopqrstuvwxyz', 'abcdefg', 24, options)
  end

  def test_match_main
    options = DMP.resolve_options({})

    # Full match.
    # Shortcut matches.
    assert_equal 0, DMP.match_main('abcdef', 'abcdef', 1000, options)

    assert_equal(-1, DMP.match_main('', 'abcdef', 1, options))

    assert_equal 3, DMP.match_main('abcdef', '', 3, options)

    assert_equal 3, DMP.match_main('abcdef', 'de', 3, options)

    # Beyond end match.
    assert_equal 3, DMP.match_main('abcdef', 'defy', 4, options)

    # Oversized pattern.
    assert_equal 0, DMP.match_main('abcdef', 'abcdefy', 0, options)

    # Complex match.
    assert_equal 4, DMP.match_main('I am the very model of a modern major general.', ' that berry ', 5, options)

    # Test null inputs.
    err = assert_raises(DMP::Error) { DMP.match_main(nil, nil, 0, options) }
    assert_equal 'Null input. (match_main)', err.message
  end
end
