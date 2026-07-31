# frozen_string_literal: true

require_relative 'test_helper'

# The port is a set of stateless module functions; these tests hammer the
# public API from many threads at once and check every result against the
# serially-computed answer.
# noinspection RbsMissingTypeSignature
class ThreadSafetyTest < Minitest::Test
  THREADS = 8
  ITERATIONS = 50

  def test_concurrent_diff_match_patch
    rng = Random.new(1234)
    alphabet = ('a'..'e').to_a << "\n"
    cases = Array.new(THREADS) do
      text1 = Array.new(rng.rand(200..400)) { alphabet.sample(random: rng) }.join
      text2 = +text1
      rng.rand(3..8).times do
        pos = rng.rand(text2.length)
        text2 = text2[0...pos] + Array.new(rng.rand(1..10)) { alphabet.sample(random: rng) }.join + text2[pos..]
      end
      [text1, text2]
    end

    # diff_timeout 0 keeps results deterministic (no wall-clock cutoffs).
    options = { diff_timeout: 0 }
    expected = cases.map do |(text1, text2)|
      diffs = DMP.diff_main(text1, text2, options)
      patches = DMP.patch_make(text1, text2, nil, options)
      [diffs, DMP.patch_to_text(patches), DMP.patch_apply(patches, text1, options)]
    end

    failures = Queue.new
    threads = Array.new(THREADS) do |t|
      Thread.new do
        text1, text2 = cases[t]
        ITERATIONS.times do
          diffs = DMP.diff_main(text1, text2, options)
          patches = DMP.patch_make(text1, text2, nil, options)
          actual = [diffs, DMP.patch_to_text(patches), DMP.patch_apply(patches, text1, options)]
          failures << [t, expected[t], actual] unless actual == expected[t]
        end
      end
    end
    threads.each(&:join)

    assert_empty failures.size.times.map { failures.pop }
  end

  def test_concurrent_shared_frozen_options
    # A frozen options object can be shared across threads.
    options = DMP.resolve_options(diff_timeout: 0).freeze
    expected = DMP.diff_main('The quick brown fox', 'The slow green fox', options)

    results = Array.new(THREADS) do
      Thread.new do
        Array.new(ITERATIONS) { DMP.diff_main('The quick brown fox', 'The slow green fox', options) }
      end
    end.flat_map(&:value)

    results.each { |r| assert_equal expected, r }
  end

  def test_default_options_frozen
    assert_predicate DMP::DEFAULT_OPTIONS, :frozen?
  end

  def test_ractor_shareable
    # Stateless module functions also work from Ractors (true parallelism).
    skip 'Ractor not available' unless defined?(Ractor)

    expected = DMP.diff_main('abc', 'ab123c', { diff_timeout: 0 })
    ractors = Array.new(4) do
      Ractor.new do
        DiffMatchPatchES.diff_main('abc', 'ab123c', { diff_timeout: 0 })
      end
    end
    ractors.each do |r|
      # Ractor#value replaced #take in Ruby 4.0.
      result = r.respond_to?(:value) ? r.value : r.take
      assert_equal expected, result
    end
  end
end
