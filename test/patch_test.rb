# frozen_string_literal: true

require_relative 'test_helper'

class PatchTest < Minitest::Test
  DIFF_DELETE = DMP::DIFF_DELETE
  DIFF_INSERT = DMP::DIFF_INSERT
  DIFF_EQUAL = DMP::DIFF_EQUAL

  def test_patch_obj
    # Patch Object.
    p = DMP.create_patch
    p.start1 = 20
    p.start2 = 21
    p.length1 = 18
    p.length2 = 17
    p.diffs = [[DIFF_EQUAL, 'jump'], [DIFF_DELETE, 's'], [DIFF_INSERT, 'ed'], [DIFF_EQUAL, ' over '],
               [DIFF_DELETE, 'the'], [DIFF_INSERT, 'a'], [DIFF_EQUAL, "\nlaz"]]
    assert_equal "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n", p.to_s
  end

  def test_patch_from_text
    assert_empty DMP.patch_from_text('')

    strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n"
    assert_equal strp, DMP.patch_from_text(strp)[0].to_s

    assert_equal "@@ -1 +1 @@\n-a\n+b\n", DMP.patch_from_text("@@ -1 +1 @@\n-a\n+b\n")[0].to_s

    assert_equal "@@ -1,3 +0,0 @@\n-abc\n", DMP.patch_from_text("@@ -1,3 +0,0 @@\n-abc\n")[0].to_s

    assert_equal "@@ -0,0 +1,3 @@\n+abc\n", DMP.patch_from_text("@@ -0,0 +1,3 @@\n+abc\n")[0].to_s

    # Generates error.
    err = assert_raises(DMP::Error) { DMP.patch_from_text("Bad\nPatch\n") }
    assert_equal 'Invalid patch string: Bad', err.message
  end

  def test_patch_to_text
    strp = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n"
    p = DMP.patch_from_text(strp)
    assert_equal strp, DMP.patch_to_text(p)

    strp = "@@ -1,9 +1,9 @@\n-f\n+F\n oo+fooba\n@@ -7,9 +7,9 @@\n obar\n-,\n+.\n  tes\n"
    p = DMP.patch_from_text(strp)
    assert_equal strp, DMP.patch_to_text(p)
  end

  def test_patch_add_context
    options = DMP.resolve_options({})

    options.patch_margin = 4
    p = DMP.patch_from_text("@@ -21,4 +21,10 @@\n-jump\n+somersault\n")[0]
    DMP.patch_add_context(p, 'The quick brown fox jumps over the lazy dog.', options)
    assert_equal "@@ -17,12 +17,18 @@\n fox \n-jump\n+somersault\n s ov\n", p.to_s

    # Same, but not enough trailing context.
    p = DMP.patch_from_text("@@ -21,4 +21,10 @@\n-jump\n+somersault\n")[0]
    DMP.patch_add_context(p, 'The quick brown fox jumps.', options)
    assert_equal "@@ -17,10 +17,16 @@\n fox \n-jump\n+somersault\n s.\n", p.to_s

    # Same, but not enough leading context.
    p = DMP.patch_from_text("@@ -3 +3,2 @@\n-e\n+at\n")[0]
    DMP.patch_add_context(p, 'The quick brown fox jumps.', options)
    assert_equal "@@ -1,7 +1,8 @@\n Th\n-e\n+at\n  qui\n", p.to_s

    # Same, but with ambiguity.
    p = DMP.patch_from_text("@@ -3 +3,2 @@\n-e\n+at\n")[0]
    DMP.patch_add_context(p, 'The quick brown fox jumps.  The quick brown fox crashes.', options)
    assert_equal "@@ -1,27 +1,28 @@\n Th\n-e\n+at\n  quick brown fox jumps. \n", p.to_s
  end

  def test_patch_make
    options = DMP.resolve_options({})

    # Null case.
    patches = DMP.patch_make('', '', nil, options)
    assert_equal '', DMP.patch_to_text(patches)

    text1 = 'The quick brown fox jumps over the lazy dog.'
    text2 = 'That quick brown fox jumped over a lazy dog.'
    # Text2+Text1 inputs.
    expected_patch = "@@ -1,8 +1,7 @@\n Th\n-at\n+e\n  qui\n@@ -21,17 +21,18 @@\n jump\n-ed\n+s\n  over \n-a\n+the\n  laz\n"
    # The second patch must be "-21,17 +21,18", not "-22,17 +21,18" due to rolling context.
    patches = DMP.patch_make(text2, text1, nil, options)
    assert_equal expected_patch, DMP.patch_to_text(patches)

    # Text1+Text2 inputs.
    expected_patch = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n"
    patches = DMP.patch_make(text1, text2, nil, options)
    assert_equal expected_patch, DMP.patch_to_text(patches)

    # Diff input.
    diffs = DMP.diff_main(text1, text2, options)
    patches = DMP.patch_make(diffs, nil, nil, options)
    assert_equal expected_patch, DMP.patch_to_text(patches)

    # Text1+Diff inputs.
    patches = DMP.patch_make(text1, diffs, nil, options)
    assert_equal expected_patch, DMP.patch_to_text(patches)

    # Text1+Text2+Diff inputs (deprecated).
    patches = DMP.patch_make(text1, text2, diffs, options)
    assert_equal expected_patch, DMP.patch_to_text(patches)

    # Character encoding.
    patches = DMP.patch_make("`1234567890-=[]\\;',./", '~!@#$%^&*()_+{}|:"<>?')
    assert_equal "@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n",
                 DMP.patch_to_text(patches)

    # Character decoding.
    diffs = [[DIFF_DELETE, "`1234567890-=[]\\;',./"], [DIFF_INSERT, '~!@#$%^&*()_+{}|:"<>?']]
    assert_equal diffs, DMP.patch_from_text(DMP.patch_to_text(patches))[0].diffs

    # Long string with repeats.
    text1 = 'abcdef' * 100
    text2 = "#{text1}123"
    expected_patch = "@@ -573,28 +573,31 @@\n cdefabcdefabcdefabcdefabcdef\n+123\n"
    patches = DMP.patch_make(text1, text2, nil, options)
    assert_equal expected_patch, DMP.patch_to_text(patches)

    # Test null inputs.
    err = assert_raises(DMP::Error) { DMP.patch_make(nil) }
    assert_equal 'Unknown call format to patch_make.', err.message
  end

  def test_patch_split_max
    options = DMP.resolve_options({})

    # Assumes that match_max_bits is 32.
    patches = DMP.patch_make('abcdefghijklmnopqrstuvwxyz01234567890', 'XabXcdXefXghXijXklXmnXopXqrXstXuvXwxXyzX01X23X45X67X89X0')
    DMP.patch_split_max(patches, options)
    assert_equal "@@ -1,32 +1,46 @@\n+X\n ab\n+X\n cd\n+X\n ef\n+X\n gh\n+X\n ij\n+X\n kl\n+X\n mn\n+X\n op\n+X\n qr\n" \
                 "+X\n st\n+X\n uv\n+X\n wx\n+X\n yz\n+X\n 012345\n@@ -25,13 +39,18 @@\n zX01\n+X\n 23\n+X\n 45\n" \
                 "+X\n 67\n+X\n 89\n+X\n 0\n",
                 DMP.patch_to_text(patches)

    patches = DMP.patch_make(
      'abcdef1234567890123456789012345678901234567890123456789012345678901234567890uvwxyz', 'abcdefuvwxyz'
    )
    old_to_text = DMP.patch_to_text(patches)
    DMP.patch_split_max(patches, options)
    assert_equal old_to_text, DMP.patch_to_text(patches)

    patches = DMP.patch_make('1234567890123456789012345678901234567890123456789012345678901234567890', 'abc')
    DMP.patch_split_max(patches, options)
    assert_equal "@@ -1,32 +1,4 @@\n-1234567890123456789012345678\n 9012\n@@ -29,32 +1,4 @@\n" \
                 "-9012345678901234567890123456\n 7890\n@@ -57,14 +1,3 @@\n-78901234567890\n+abc\n",
                 DMP.patch_to_text(patches)

    patches = DMP.patch_make('abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1',
                             'abcdefghij , h : 1 , t : 1 abcdefghij , h : 1 , t : 1 abcdefghij , h : 0 , t : 1')
    DMP.patch_split_max(patches, options)
    assert_equal "@@ -2,32 +2,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n" \
                 "@@ -29,32 +29,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n",
                 DMP.patch_to_text(patches)
  end

  def test_patch_add_padding
    options = DMP.resolve_options({})

    # Both edges full.
    patches = DMP.patch_make('', 'test')
    assert_equal "@@ -0,0 +1,4 @@\n+test\n", DMP.patch_to_text(patches)
    DMP.patch_add_padding(patches, options)
    assert_equal "@@ -1,8 +1,12 @@\n %01%02%03%04\n+test\n %01%02%03%04\n", DMP.patch_to_text(patches)

    # Both edges partial.
    patches = DMP.patch_make('XY', 'XtestY')
    assert_equal "@@ -1,2 +1,6 @@\n X\n+test\n Y\n", DMP.patch_to_text(patches)
    DMP.patch_add_padding(patches, options)
    assert_equal "@@ -2,8 +2,12 @@\n %02%03%04X\n+test\n Y%01%02%03\n", DMP.patch_to_text(patches)

    # Both edges none.
    patches = DMP.patch_make('XXXXYYYY', 'XXXXtestYYYY')
    assert_equal "@@ -1,8 +1,12 @@\n XXXX\n+test\n YYYY\n", DMP.patch_to_text(patches)
    DMP.patch_add_padding(patches, options)
    assert_equal "@@ -5,8 +5,12 @@\n XXXX\n+test\n YYYY\n", DMP.patch_to_text(patches)
  end

  def test_patch_apply
    options = DMP.resolve_options(match_distance: 1000, match_threshold: 0.5, patch_delete_threshold: 0.5)

    # Null case.
    patches = DMP.patch_make('', '')
    results = DMP.patch_apply(patches, 'Hello world.', options)
    assert_equal ['Hello world.', []], results

    # Exact match.
    patches = DMP.patch_make('The quick brown fox jumps over the lazy dog.',
                             'That quick brown fox jumped over a lazy dog.')
    results = DMP.patch_apply(patches, 'The quick brown fox jumps over the lazy dog.', options)
    assert_equal ['That quick brown fox jumped over a lazy dog.', [true, true]], results

    # Partial match.
    results = DMP.patch_apply(patches, 'The quick red rabbit jumps over the tired tiger.', options)
    assert_equal ['That quick red rabbit jumped over a tired tiger.', [true, true]], results

    # Failed match.
    results = DMP.patch_apply(patches, 'I am the very model of a modern major general.', options)
    assert_equal ['I am the very model of a modern major general.', [false, false]], results

    # Big delete, small change.
    patches = DMP.patch_make('x1234567890123456789012345678901234567890123456789012345678901234567890y', 'xabcy')
    results = DMP.patch_apply(patches,
                              'x123456789012345678901234567890-----++++++++++-----123456789012345678901234567890y',
                              options)
    assert_equal ['xabcy', [true, true]], results

    # Big delete, big change 1.
    patches = DMP.patch_make('x1234567890123456789012345678901234567890123456789012345678901234567890y', 'xabcy')
    results = DMP.patch_apply(patches,
                              'x12345678901234567890---------------++++++++++---------------12345678901234567890y',
                              options)
    assert_equal ['xabc12345678901234567890---------------++++++++++---------------12345678901234567890y',
                  [false, true]], results

    # Big delete, big change 2.
    options.patch_delete_threshold = 0.6
    patches = DMP.patch_make('x1234567890123456789012345678901234567890123456789012345678901234567890y', 'xabcy')
    results = DMP.patch_apply(patches,
                              'x12345678901234567890---------------++++++++++---------------12345678901234567890y',
                              options)
    assert_equal ['xabcy', [true, true]], results
    options.patch_delete_threshold = 0.5

    # Compensate for failed patch.
    options.match_threshold = 0.0
    options.match_distance = 0
    patches = DMP.patch_make('abcdefghijklmnopqrstuvwxyz--------------------1234567890',
                             'abcXXXXXXXXXXdefghijklmnopqrstuvwxyz--------------------1234567YYYYYYYYYY890')
    results = DMP.patch_apply(patches, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ--------------------1234567890', options)
    assert_equal ['ABCDEFGHIJKLMNOPQRSTUVWXYZ--------------------1234567YYYYYYYYYY890', [false, true]], results
    options.match_threshold = 0.5
    options.match_distance = 1000

    # No side effects.
    patches = DMP.patch_make('', 'test')
    patchstr = DMP.patch_to_text(patches)
    DMP.patch_apply(patches, '', options)
    assert_equal patchstr, DMP.patch_to_text(patches)

    # No side effects with major delete.
    patches = DMP.patch_make('The quick brown fox jumps over the lazy dog.', 'Woof')
    patchstr = DMP.patch_to_text(patches)
    DMP.patch_apply(patches, 'The quick brown fox jumps over the lazy dog.', options)
    assert_equal patchstr, DMP.patch_to_text(patches)

    # Edge exact match.
    patches = DMP.patch_make('', 'test')
    results = DMP.patch_apply(patches, '', options)
    assert_equal ['test', [true]], results

    # Near edge exact match.
    patches = DMP.patch_make('XY', 'XtestY')
    results = DMP.patch_apply(patches, 'XY', options)
    assert_equal ['XtestY', [true]], results

    # Edge partial match.
    patches = DMP.patch_make('y', 'y123')
    results = DMP.patch_apply(patches, 'x', options)
    assert_equal ['x123', [true]], results
  end
end
