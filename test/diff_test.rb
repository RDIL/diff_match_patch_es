# frozen_string_literal: true

require_relative 'test_helper'

class DiffTest < Minitest::Test
  DIFF_DELETE = DMP::DIFF_DELETE
  DIFF_INSERT = DMP::DIFF_INSERT
  DIFF_EQUAL = DMP::DIFF_EQUAL

  def diff_rebuild_texts(diffs)
    # Construct the two texts which made up the diff originally.
    text1 = +''
    text2 = +''
    diffs.each do |(op, data)|
      text1 << data if op != DIFF_INSERT
      text2 << data if op != DIFF_DELETE
    end
    [text1, text2]
  end

  def test_diff_common_prefix
    # Detect any common prefix.
    # Null case.
    assert_equal 0, DMP.diff_common_prefix('abc', 'xyz')

    # Non-null case.
    assert_equal 4, DMP.diff_common_prefix('1234', '1234xyz')

    # Whole case.
    assert_equal 0, DMP.diff_common_prefix('1234', 'xyz1234')
  end

  def test_diff_common_suffix
    # Detect any common suffix.
    # Null case.
    assert_equal 0, DMP.diff_common_suffix('abc', 'xyz')

    # Non-null case.
    assert_equal 4, DMP.diff_common_suffix('abcdef1234', 'xyz1234')

    # Whole case.
    assert_equal 4, DMP.diff_common_suffix('1234', 'xyz1234')
  end

  def test_diff_common_overlap
    # Detect any suffix/prefix overlap.
    # Null case.
    assert_equal 0, DMP.diff_common_overlap('', 'abcd')

    # Whole case.
    assert_equal 3, DMP.diff_common_overlap('abc', 'abcd')

    # No overlap.
    assert_equal 0, DMP.diff_common_overlap('123456', 'abcd')

    # Overlap.
    assert_equal 3, DMP.diff_common_overlap('123456xxx', 'xxxabcd')

    # Unicode.
    # Some overly clever languages (C#) may treat ligatures as equal to their
    # component letters.  E.g. U+FB01 == 'fi'
    assert_equal 0, DMP.diff_common_overlap('fi', "ﬁi")
  end

  def test_diff_half_match
    options = DMP.resolve_options(diff_timeout: 1)

    # No match.
    assert_nil DMP.diff_half_match('1234567890', 'abcdef', options)

    assert_nil DMP.diff_half_match('12345', '23', options)

    # Single Match.
    assert_equal ['12', '90', 'a', 'z', '345678'], DMP.diff_half_match('1234567890', 'a345678z', options)

    assert_equal ['a', 'z', '12', '90', '345678'], DMP.diff_half_match('a345678z', '1234567890', options)

    assert_equal ['abc', 'z', '1234', '0', '56789'], DMP.diff_half_match('abc56789z', '1234567890', options)

    assert_equal ['a', 'xyz', '1', '7890', '23456'], DMP.diff_half_match('a23456xyz', '1234567890', options)

    # Multiple Matches.
    assert_equal ['12123', '123121', 'a', 'z', '1234123451234'],
                 DMP.diff_half_match('121231234123451234123121', 'a1234123451234z', options)

    assert_equal ['', '-=-=-=-=-=', 'x', '', 'x-=-=-=-=-=-=-='],
                 DMP.diff_half_match('x-=-=-=-=-=-=-=-=-=-=-=-=', 'xx-=-=-=-=-=-=-=', options)

    assert_equal ['-=-=-=-=-=', '', '', 'y', '-=-=-=-=-=-=-=y'],
                 DMP.diff_half_match('-=-=-=-=-=-=-=-=-=-=-=-=y', '-=-=-=-=-=-=-=yy', options)

    # Non-optimal halfmatch.
    # Optimal diff would be -q+x=H-i+e=lloHe+Hu=llo-Hew+y not -qHillo+x=HelloHe-w+Hulloy
    assert_equal ['qHillo', 'w', 'x', 'Hulloy', 'HelloHe'],
                 DMP.diff_half_match('qHilloHelloHew', 'xHelloHeHulloy', options)

    # Optimal no halfmatch.
    options.diff_timeout = 0
    assert_nil DMP.diff_half_match('qHilloHelloHew', 'xHelloHeHulloy', options)
  end

  def test_diff_lines_to_chars
    # Convert lines down to characters.
    assert_equal({ chars1: "\x01\x02\x01", chars2: "\x02\x01\x02", line_array: ['', "alpha\n", "beta\n"] },
                 DMP.diff_lines_to_chars("alpha\nbeta\nalpha\n", "beta\nalpha\nbeta\n"))

    assert_equal({ chars1: '', chars2: "\x01\x02\x03\x03", line_array: ['', "alpha\r\n", "beta\r\n", "\r\n"] },
                 DMP.diff_lines_to_chars('', "alpha\r\nbeta\r\n\r\n\r\n"))

    assert_equal({ chars1: "\x01", chars2: "\x02", line_array: ['', 'a', 'b'] },
                 DMP.diff_lines_to_chars('a', 'b'))

    # More than 256 to reveal any 8-bit limitations.
    n = 300
    line_list = (1..n).map { |i| "#{i}\n" }
    char_list = (1..n).map { |i| i.chr(Encoding::UTF_8) }
    assert_equal n, line_list.length
    lines = line_list.join
    chars = char_list.join
    assert_equal n, chars.length
    line_list.unshift('')
    assert_equal({ chars1: chars, chars2: '', line_array: line_list },
                 DMP.diff_lines_to_chars(lines, ''))
  end

  def test_diff_chars_to_lines
    # Convert chars up to lines.
    diffs = [[DIFF_EQUAL, "\x01\x02\x01"], [DIFF_INSERT, "\x02\x01\x02"]]
    DMP.diff_chars_to_lines!(diffs, ['', "alpha\n", "beta\n"])
    assert_equal [[DIFF_EQUAL, "alpha\nbeta\nalpha\n"], [DIFF_INSERT, "beta\nalpha\nbeta\n"]], diffs

    # More than 256 to reveal any 8-bit limitations.
    n = 300
    line_list = (1..n).map { |i| "#{i}\n" }
    char_list = (1..n).map { |i| i.chr(Encoding::UTF_8) }
    assert_equal n, line_list.length
    lines = line_list.join
    chars = char_list.join
    assert_equal n, chars.length
    line_list.unshift('')

    diffs = [[DIFF_DELETE, chars]]
    DMP.diff_chars_to_lines!(diffs, line_list)
    assert_equal [[DIFF_DELETE, lines]], diffs

    # More than 65536 to verify any 16-bit limitation.
    line_list = (0...66_000).map { |i| "#{i}\n" }
    chars = line_list.join
    results = DMP.diff_lines_to_chars(chars, '')
    diffs = [[DIFF_INSERT, results[:chars1]]]
    DMP.diff_chars_to_lines!(diffs, results[:line_array])
    assert_equal chars, diffs[0][1]
  end

  def test_diff_cleanup_merge
    # Cleanup a messy diff.
    # Null case.
    diffs = []
    DMP.diff_cleanup_merge!(diffs)
    assert_empty diffs

    # No change case.
    diffs = [[DIFF_EQUAL, 'a'], [DIFF_DELETE, 'b'], [DIFF_INSERT, 'c']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_EQUAL, 'a'], [DIFF_DELETE, 'b'], [DIFF_INSERT, 'c']], diffs

    # Merge equalities.
    diffs = [[DIFF_EQUAL, 'a'], [DIFF_EQUAL, 'b'], [DIFF_EQUAL, 'c']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_EQUAL, 'abc']], diffs

    # Merge deletions.
    diffs = [[DIFF_DELETE, 'a'], [DIFF_DELETE, 'b'], [DIFF_DELETE, 'c']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_DELETE, 'abc']], diffs

    # Merge insertions.
    diffs = [[DIFF_INSERT, 'a'], [DIFF_INSERT, 'b'], [DIFF_INSERT, 'c']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_INSERT, 'abc']], diffs

    # Merge interweave.
    diffs = [[DIFF_DELETE, 'a'], [DIFF_INSERT, 'b'], [DIFF_DELETE, 'c'], [DIFF_INSERT, 'd'],
             [DIFF_EQUAL, 'e'], [DIFF_EQUAL, 'f']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_DELETE, 'ac'], [DIFF_INSERT, 'bd'], [DIFF_EQUAL, 'ef']], diffs

    # Prefix and suffix detection.
    diffs = [[DIFF_DELETE, 'a'], [DIFF_INSERT, 'abc'], [DIFF_DELETE, 'dc']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_EQUAL, 'a'], [DIFF_DELETE, 'd'], [DIFF_INSERT, 'b'], [DIFF_EQUAL, 'c']], diffs

    # Prefix and suffix detection with equalities.
    diffs = [[DIFF_EQUAL, 'x'], [DIFF_DELETE, 'a'], [DIFF_INSERT, 'abc'], [DIFF_DELETE, 'dc'], [DIFF_EQUAL, 'y']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_EQUAL, 'xa'], [DIFF_DELETE, 'd'], [DIFF_INSERT, 'b'], [DIFF_EQUAL, 'cy']], diffs

    # Slide edit left.
    diffs = [[DIFF_EQUAL, 'a'], [DIFF_INSERT, 'ba'], [DIFF_EQUAL, 'c']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_INSERT, 'ab'], [DIFF_EQUAL, 'ac']], diffs

    # Slide edit right.
    diffs = [[DIFF_EQUAL, 'c'], [DIFF_INSERT, 'ab'], [DIFF_EQUAL, 'a']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_EQUAL, 'ca'], [DIFF_INSERT, 'ba']], diffs

    # Slide edit left recursive.
    diffs = [[DIFF_EQUAL, 'a'], [DIFF_DELETE, 'b'], [DIFF_EQUAL, 'c'], [DIFF_DELETE, 'ac'], [DIFF_EQUAL, 'x']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_DELETE, 'abc'], [DIFF_EQUAL, 'acx']], diffs

    # Slide edit right recursive.
    diffs = [[DIFF_EQUAL, 'x'], [DIFF_DELETE, 'ca'], [DIFF_EQUAL, 'c'], [DIFF_DELETE, 'b'], [DIFF_EQUAL, 'a']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_EQUAL, 'xca'], [DIFF_DELETE, 'cba']], diffs

    # Empty merge.
    diffs = [[DIFF_DELETE, 'b'], [DIFF_INSERT, 'ab'], [DIFF_EQUAL, 'c']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_INSERT, 'a'], [DIFF_EQUAL, 'bc']], diffs

    # Empty equality.
    diffs = [[DIFF_EQUAL, ''], [DIFF_INSERT, 'a'], [DIFF_EQUAL, 'b']]
    DMP.diff_cleanup_merge!(diffs)
    assert_equal [[DIFF_INSERT, 'a'], [DIFF_EQUAL, 'b']], diffs
  end

  def test_diff_cleanup_semantic_lossless
    # Cleanup semantically trivial equalities.
    # Null case.
    diffs = []
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_empty diffs

    # Blank lines.
    diffs = [[DIFF_EQUAL, "AAA\r\n\r\nBBB"], [DIFF_INSERT, "\r\nDDD\r\n\r\nBBB"], [DIFF_EQUAL, "\r\nEEE"]]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_EQUAL, "AAA\r\n\r\n"], [DIFF_INSERT, "BBB\r\nDDD\r\n\r\n"], [DIFF_EQUAL, "BBB\r\nEEE"]], diffs

    # Line boundaries.
    diffs = [[DIFF_EQUAL, "AAA\r\nBBB"], [DIFF_INSERT, " DDD\r\nBBB"], [DIFF_EQUAL, ' EEE']]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_EQUAL, "AAA\r\n"], [DIFF_INSERT, "BBB DDD\r\n"], [DIFF_EQUAL, 'BBB EEE']], diffs

    # Word boundaries.
    diffs = [[DIFF_EQUAL, 'The c'], [DIFF_INSERT, 'ow and the c'], [DIFF_EQUAL, 'at.']]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_EQUAL, 'The '], [DIFF_INSERT, 'cow and the '], [DIFF_EQUAL, 'cat.']], diffs

    # Alphanumeric boundaries.
    diffs = [[DIFF_EQUAL, 'The-c'], [DIFF_INSERT, 'ow-and-the-c'], [DIFF_EQUAL, 'at.']]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_EQUAL, 'The-'], [DIFF_INSERT, 'cow-and-the-'], [DIFF_EQUAL, 'cat.']], diffs

    # Hitting the start.
    diffs = [[DIFF_EQUAL, 'a'], [DIFF_DELETE, 'a'], [DIFF_EQUAL, 'ax']]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_DELETE, 'a'], [DIFF_EQUAL, 'aax']], diffs

    # Hitting the end.
    diffs = [[DIFF_EQUAL, 'xa'], [DIFF_DELETE, 'a'], [DIFF_EQUAL, 'a']]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_EQUAL, 'xaa'], [DIFF_DELETE, 'a']], diffs

    # Sentence boundaries.
    diffs = [[DIFF_EQUAL, 'The xxx. The '], [DIFF_INSERT, 'zzz. The '], [DIFF_EQUAL, 'yyy.']]
    DMP.diff_cleanup_semantic_lossless!(diffs)
    assert_equal [[DIFF_EQUAL, 'The xxx.'], [DIFF_INSERT, ' The zzz.'], [DIFF_EQUAL, ' The yyy.']], diffs
  end

  def test_diff_cleanup_semantic
    # Cleanup semantically trivial equalities.
    # Null case.
    diffs = []
    DMP.diff_cleanup_semantic!(diffs)
    assert_empty diffs

    # No elimination #1.
    diffs = [[DIFF_DELETE, 'ab'], [DIFF_INSERT, 'cd'], [DIFF_EQUAL, '12'], [DIFF_DELETE, 'e']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'ab'], [DIFF_INSERT, 'cd'], [DIFF_EQUAL, '12'], [DIFF_DELETE, 'e']], diffs

    # No elimination #2.
    diffs = [[DIFF_DELETE, 'abc'], [DIFF_INSERT, 'ABC'], [DIFF_EQUAL, '1234'], [DIFF_DELETE, 'wxyz']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'abc'], [DIFF_INSERT, 'ABC'], [DIFF_EQUAL, '1234'], [DIFF_DELETE, 'wxyz']], diffs

    # Simple elimination.
    diffs = [[DIFF_DELETE, 'a'], [DIFF_EQUAL, 'b'], [DIFF_DELETE, 'c']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'abc'], [DIFF_INSERT, 'b']], diffs

    # Backpass elimination.
    diffs = [[DIFF_DELETE, 'ab'], [DIFF_EQUAL, 'cd'], [DIFF_DELETE, 'e'], [DIFF_EQUAL, 'f'], [DIFF_INSERT, 'g']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'abcdef'], [DIFF_INSERT, 'cdfg']], diffs

    # Multiple eliminations.
    diffs = [[DIFF_INSERT, '1'], [DIFF_EQUAL, 'A'], [DIFF_DELETE, 'B'], [DIFF_INSERT, '2'], [DIFF_EQUAL, '_'],
             [DIFF_INSERT, '1'], [DIFF_EQUAL, 'A'], [DIFF_DELETE, 'B'], [DIFF_INSERT, '2']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'AB_AB'], [DIFF_INSERT, '1A2_1A2']], diffs

    # Word boundaries.
    diffs = [[DIFF_EQUAL, 'The c'], [DIFF_DELETE, 'ow and the c'], [DIFF_EQUAL, 'at.']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_EQUAL, 'The '], [DIFF_DELETE, 'cow and the '], [DIFF_EQUAL, 'cat.']], diffs

    # No overlap elimination.
    diffs = [[DIFF_DELETE, 'abcxx'], [DIFF_INSERT, 'xxdef']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'abcxx'], [DIFF_INSERT, 'xxdef']], diffs

    # Overlap elimination.
    diffs = [[DIFF_DELETE, 'abcxxx'], [DIFF_INSERT, 'xxxdef']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'abc'], [DIFF_EQUAL, 'xxx'], [DIFF_INSERT, 'def']], diffs

    # Reverse overlap elimination.
    diffs = [[DIFF_DELETE, 'xxxabc'], [DIFF_INSERT, 'defxxx']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_INSERT, 'def'], [DIFF_EQUAL, 'xxx'], [DIFF_DELETE, 'abc']], diffs

    # Two overlap eliminations.
    diffs = [[DIFF_DELETE, 'abcd1212'], [DIFF_INSERT, '1212efghi'], [DIFF_EQUAL, '----'],
             [DIFF_DELETE, 'A3'], [DIFF_INSERT, '3BC']]
    DMP.diff_cleanup_semantic!(diffs)
    assert_equal [[DIFF_DELETE, 'abcd'], [DIFF_EQUAL, '1212'], [DIFF_INSERT, 'efghi'], [DIFF_EQUAL, '----'],
                  [DIFF_DELETE, 'A'], [DIFF_EQUAL, '3'], [DIFF_INSERT, 'BC']], diffs
  end

  def test_diff_cleanup_efficiency
    options = DMP.resolve_options(diff_edit_cost: 4)

    # Null case.
    diffs = []
    DMP.diff_cleanup_efficiency!(diffs, options)
    assert_empty diffs

    # No elimination.
    diffs = [[DIFF_DELETE, 'ab'], [DIFF_INSERT, '12'], [DIFF_EQUAL, 'wxyz'], [DIFF_DELETE, 'cd'], [DIFF_INSERT, '34']]
    DMP.diff_cleanup_efficiency!(diffs, options)
    assert_equal [[DIFF_DELETE, 'ab'], [DIFF_INSERT, '12'], [DIFF_EQUAL, 'wxyz'], [DIFF_DELETE, 'cd'],
                  [DIFF_INSERT, '34']], diffs

    # Four-edit elimination.
    diffs = [[DIFF_DELETE, 'ab'], [DIFF_INSERT, '12'], [DIFF_EQUAL, 'xyz'], [DIFF_DELETE, 'cd'], [DIFF_INSERT, '34']]
    DMP.diff_cleanup_efficiency!(diffs, options)
    assert_equal [[DIFF_DELETE, 'abxyzcd'], [DIFF_INSERT, '12xyz34']], diffs

    # Three-edit elimination.
    diffs = [[DIFF_INSERT, '12'], [DIFF_EQUAL, 'x'], [DIFF_DELETE, 'cd'], [DIFF_INSERT, '34']]
    DMP.diff_cleanup_efficiency!(diffs, options)
    assert_equal [[DIFF_DELETE, 'xcd'], [DIFF_INSERT, '12x34']], diffs

    # Backpass elimination.
    diffs = [[DIFF_DELETE, 'ab'], [DIFF_INSERT, '12'], [DIFF_EQUAL, 'xy'], [DIFF_INSERT, '34'], [DIFF_EQUAL, 'z'],
             [DIFF_DELETE, 'cd'], [DIFF_INSERT, '56']]
    DMP.diff_cleanup_efficiency!(diffs, options)
    assert_equal [[DIFF_DELETE, 'abxyzcd'], [DIFF_INSERT, '12xy34z56']], diffs

    # High cost elimination.
    options.diff_edit_cost = 5
    diffs = [[DIFF_DELETE, 'ab'], [DIFF_INSERT, '12'], [DIFF_EQUAL, 'wxyz'], [DIFF_DELETE, 'cd'], [DIFF_INSERT, '34']]
    DMP.diff_cleanup_efficiency!(diffs, options)
    assert_equal [[DIFF_DELETE, 'abwxyzcd'], [DIFF_INSERT, '12wxyz34']], diffs
  end

  def test_diff_pretty_html
    # Pretty print.
    diffs = [[DIFF_EQUAL, "a\n"], [DIFF_DELETE, '<B>b</B>'], [DIFF_INSERT, 'c&d']]
    assert_equal '<span>a&para;<br></span><del style="background:#ffe6e6;">&lt;B&gt;b&lt;/B&gt;</del>' \
                 '<ins style="background:#e6ffe6;">c&amp;d</ins>',
                 DMP.diff_pretty_html(diffs)
  end

  def test_diff_text
    # Compute the source and destination texts.
    diffs = [[DIFF_EQUAL, 'jump'], [DIFF_DELETE, 's'], [DIFF_INSERT, 'ed'], [DIFF_EQUAL, ' over '],
             [DIFF_DELETE, 'the'], [DIFF_INSERT, 'a'], [DIFF_EQUAL, ' lazy']]
    assert_equal 'jumps over the lazy', DMP.diff_text1(diffs)
    assert_equal 'jumped over a lazy', DMP.diff_text2(diffs)
  end

  def test_diff_delta
    # Convert a diff into delta string.
    diffs = [[DIFF_EQUAL, 'jump'], [DIFF_DELETE, 's'], [DIFF_INSERT, 'ed'], [DIFF_EQUAL, ' over '],
             [DIFF_DELETE, 'the'], [DIFF_INSERT, 'a'], [DIFF_EQUAL, ' lazy'], [DIFF_INSERT, 'old dog']]
    text1 = DMP.diff_text1(diffs)
    assert_equal 'jumps over the lazy', text1

    delta = DMP.diff_to_delta(diffs)
    assert_equal "=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", delta

    # Convert delta string into a diff.
    assert_equal diffs, DMP.diff_from_delta(text1, delta)

    # Generates error (19 != 20).
    err = assert_raises(DMP::Error) { DMP.diff_from_delta("#{text1}x", delta) }
    assert_equal 'Delta length (19) does not equal source text length (20).', err.message

    # Generates error (19 != 18).
    err = assert_raises(DMP::Error) { DMP.diff_from_delta(text1[1..], delta) }
    assert_equal 'Delta length (19) does not equal source text length (18).', err.message

    # Generates error (%c3%xy invalid Unicode).
    err = assert_raises(DMP::Error) { DMP.diff_from_delta('', '+%c3%xy') }
    assert_equal 'Illegal escape in diff_fromDelta: %c3%xy', err.message

    # Test deltas with special characters.
    diffs = [[DIFF_EQUAL, "ڀ \x00 \t %"], [DIFF_DELETE, "ځ \x01 \n ^"], [DIFF_INSERT, "ڂ \x02 \\ |"]]
    text1 = DMP.diff_text1(diffs)
    assert_equal "ڀ \x00 \t %ځ \x01 \n ^", text1

    delta = DMP.diff_to_delta(diffs)
    assert_equal "=7\t-7\t+%DA%82 %02 %5C %7C", delta

    # Convert delta string into a diff.
    assert_equal diffs, DMP.diff_from_delta(text1, delta)

    # Verify pool of unchanged characters.
    diffs = [[DIFF_INSERT, "A-Z a-z 0-9 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # "]]
    text2 = DMP.diff_text2(diffs)
    assert_equal "A-Z a-z 0-9 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ", text2

    delta = DMP.diff_to_delta(diffs)
    assert_equal "+A-Z a-z 0-9 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ", delta

    # Convert delta string into a diff.
    assert_equal diffs, DMP.diff_from_delta('', delta)

    # 160 kb string.
    a = 'abcdefghij'
    14.times { a += a }

    diffs = [[DIFF_INSERT, a]]
    delta = DMP.diff_to_delta(diffs)
    assert_equal "+#{a}", delta

    # Convert delta string into a diff.
    assert_equal diffs, DMP.diff_from_delta('', delta)
  end

  def test_diff_x_index
    # Translate a location in text1 to text2.
    # Translation on equality.
    assert_equal 5, DMP.diff_x_index([[DIFF_DELETE, 'a'], [DIFF_INSERT, '1234'], [DIFF_EQUAL, 'xyz']], 2)

    # Translation on deletion.
    assert_equal 1, DMP.diff_x_index([[DIFF_EQUAL, 'a'], [DIFF_DELETE, '1234'], [DIFF_EQUAL, 'xyz']], 3)
  end

  def test_diff_levenshtein
    # Levenshtein with trailing equality.
    assert_equal 4, DMP.diff_levenshtein([[DIFF_DELETE, 'abc'], [DIFF_INSERT, '1234'], [DIFF_EQUAL, 'xyz']])

    # Levenshtein with leading equality.
    assert_equal 4, DMP.diff_levenshtein([[DIFF_EQUAL, 'xyz'], [DIFF_DELETE, 'abc'], [DIFF_INSERT, '1234']])

    # Levenshtein with middle equality.
    assert_equal 7, DMP.diff_levenshtein([[DIFF_DELETE, 'abc'], [DIFF_EQUAL, 'xyz'], [DIFF_INSERT, '1234']])
  end

  def test_diff_bisect
    options = DMP.resolve_options({})
    # Normal.
    a = 'cat'
    b = 'map'
    # Since the resulting diff hasn't been normalized, it would be ok if
    # the insertion and deletion pairs are swapped.
    # If the order changes, tweak this test as required.
    assert_equal [[DIFF_DELETE, 'c'], [DIFF_INSERT, 'm'], [DIFF_EQUAL, 'a'], [DIFF_DELETE, 't'], [DIFF_INSERT, 'p']],
                 DMP.diff_bisect(a, b, options, Float::MAX)

    # Timeout.
    assert_equal [[DIFF_DELETE, 'cat'], [DIFF_INSERT, 'map']], DMP.diff_bisect(a, b, options, 0)
  end

  def test_diff_main
    options = DMP.resolve_options({})

    # Perform a trivial diff.
    # Null case.
    assert_empty DMP.diff_main('', '', options)

    # Equality.
    assert_equal [[DIFF_EQUAL, 'abc']], DMP.diff_main('abc', 'abc', options)

    # Simple insertion.
    assert_equal [[DIFF_EQUAL, 'ab'], [DIFF_INSERT, '123'], [DIFF_EQUAL, 'c']], DMP.diff_main('abc', 'ab123c', options)

    # Simple deletion.
    assert_equal [[DIFF_EQUAL, 'a'], [DIFF_DELETE, '123'], [DIFF_EQUAL, 'bc']], DMP.diff_main('a123bc', 'abc', options)

    # Two insertions.
    assert_equal [[DIFF_EQUAL, 'a'], [DIFF_INSERT, '123'], [DIFF_EQUAL, 'b'], [DIFF_INSERT, '456'], [DIFF_EQUAL, 'c']],
                 DMP.diff_main('abc', 'a123b456c', options)

    # Two deletions.
    assert_equal [[DIFF_EQUAL, 'a'], [DIFF_DELETE, '123'], [DIFF_EQUAL, 'b'], [DIFF_DELETE, '456'], [DIFF_EQUAL, 'c']],
                 DMP.diff_main('a123b456c', 'abc', options)

    # Perform a real diff.
    # Switch off the timeout.
    options.diff_timeout = 0
    # Simple cases.
    assert_equal [[DIFF_DELETE, 'a'], [DIFF_INSERT, 'b']], DMP.diff_main('a', 'b', options)

    assert_equal [[DIFF_DELETE, 'Apple'], [DIFF_INSERT, 'Banana'], [DIFF_EQUAL, 's are a'], [DIFF_INSERT, 'lso'],
                  [DIFF_EQUAL, ' fruit.']],
                 DMP.diff_main('Apples are a fruit.', 'Bananas are also fruit.', options)

    assert_equal [[DIFF_DELETE, 'a'], [DIFF_INSERT, "ڀ"], [DIFF_EQUAL, 'x'], [DIFF_DELETE, "\t"],
                  [DIFF_INSERT, "\0"]],
                 DMP.diff_main("ax\t", "ڀx\0", options)

    # Overlaps.
    assert_equal [[DIFF_DELETE, '1'], [DIFF_EQUAL, 'a'], [DIFF_DELETE, 'y'], [DIFF_EQUAL, 'b'], [DIFF_DELETE, '2'],
                  [DIFF_INSERT, 'xab']],
                 DMP.diff_main('1ayb2', 'abxab', options)

    assert_equal [[DIFF_INSERT, 'xaxcx'], [DIFF_EQUAL, 'abc'], [DIFF_DELETE, 'y']],
                 DMP.diff_main('abcy', 'xaxcxabc', options)

    assert_equal [[DIFF_DELETE, 'ABCD'], [DIFF_EQUAL, 'a'], [DIFF_DELETE, '='], [DIFF_INSERT, '-'],
                  [DIFF_EQUAL, 'bcd'], [DIFF_DELETE, '='], [DIFF_INSERT, '-'], [DIFF_EQUAL, 'efghijklmnopqrs'],
                  [DIFF_DELETE, 'EFGHIJKLMNOefg']],
                 DMP.diff_main('ABCDa=bcd=efghijklmnopqrsEFGHIJKLMNOefg', 'a-bcd-efghijklmnopqrs', options)

    # Large equality.
    assert_equal [[DIFF_INSERT, ' '], [DIFF_EQUAL, 'a'], [DIFF_INSERT, 'nd'], [DIFF_EQUAL, ' [[Pennsylvania]]'],
                  [DIFF_DELETE, ' and [[New']],
                 DMP.diff_main('a [[Pennsylvania]] and [[New', ' and [[Pennsylvania]]', options)

    # Timeout.
    options.diff_timeout = 0.1 # 100ms
    a = "`Twas brillig, and the slithy toves\nDid gyre and gimble in the wabe:\n" \
        "All mimsy were the borogoves,\nAnd the mome raths outgrabe.\n"
    b = "I am the very model of a modern major general,\nI've information vegetable, animal, and mineral,\n" \
        "I know the kings of England, and I quote the fights historical,\n" \
        "From Marathon to Waterloo, in order categorical.\n"
    # Increase the text lengths by 1024 times to ensure a timeout.
    10.times do
      a += a
      b += b
    end
    start_time = DMP.now_ms
    DMP.diff_main(a, b, options)
    end_time = DMP.now_ms
    # Test that we took at least the timeout period.
    assert_operator options.diff_timeout * 1000, :<=, end_time - start_time
    # Test that we didn't take forever (be forgiving).
    # Theoretically this test could fail very occasionally if the
    # OS task swaps or locks up for a second at the wrong moment.
    assert_operator options.diff_timeout * 1000 * 2, :>, end_time - start_time
    options.diff_timeout = 0

    # Test the linemode speedup.
    # Must be long to pass the 100 char cutoff.
    # Simple line-mode.
    a = "1234567890\n" * 13
    b = "abcdefghij\n" * 13
    assert_equal DMP.diff_main(a, b, options, true), DMP.diff_main(a, b, options, false)

    # Single line-mode.
    a = '1234567890' * 13
    b = 'abcdefghij' * 13
    assert_equal DMP.diff_main(a, b, options, true), DMP.diff_main(a, b, options, false)

    # Overlap line-mode.
    a = "1234567890\n" * 13
    b = "abcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\n" \
        "abcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n"
    texts_linemode = diff_rebuild_texts(DMP.diff_main(a, b, options, true))
    texts_textmode = diff_rebuild_texts(DMP.diff_main(a, b, options, false))
    assert_equal texts_textmode, texts_linemode

    # Test null inputs.
    err = assert_raises(DMP::Error) { DMP.diff_main(nil, nil, options) }
    assert_equal 'Null input. (diff_main)', err.message
  end
end
