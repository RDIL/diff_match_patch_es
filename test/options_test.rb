# frozen_string_literal: true

require_relative 'test_helper'

# noinspection RbsMissingTypeSignature
class OptionsTest < Minitest::Test
  # One non-default value per attribute.
  OVERRIDES = {
    diff_timeout: 2.5,
    diff_edit_cost: 6,
    match_threshold: 0.25,
    match_distance: 500,
    patch_delete_threshold: 0.75,
    patch_margin: 8,
    match_max_bits: 64
  }.freeze

  def test_to_h_reflects_constructor_arguments
    assert_equal OVERRIDES, DMP::Options.new(**OVERRIDES).to_h
  end

  def test_to_h_reflects_attribute_writers
    options = DMP::Options.new
    OVERRIDES.each { |name, value| options.public_send(:"#{name}=", value) }

    assert_equal OVERRIDES, options.to_h
  end

  def test_to_h_returns_a_detached_hash
    options = DMP::Options.new(**OVERRIDES)
    hash = options.to_h
    hash[:diff_timeout] = 99
    hash.delete(:patch_margin)

    assert_equal OVERRIDES, options.to_h
  end

  def test_to_h_round_trips_through_new
    options = DMP::Options.new(**OVERRIDES)

    assert_equal options, DMP::Options.new(**options.to_h)
  end

  def test_equal_when_all_attributes_match
    assert_equal DMP::Options.new, DMP::Options.new
    assert_equal DMP::Options.new(**OVERRIDES), DMP::Options.new(**OVERRIDES)

    # The frozen shared instance equals a fresh default.
    assert_equal DMP::DEFAULT_OPTIONS, DMP::Options.new
  end

  def test_not_equal_when_any_single_attribute_differs
    OVERRIDES.each do |name, value|
      refute_equal DMP::Options.new, DMP::Options.new(name => value), "#{name} should affect equality"
    end
  end

  def test_equality_tracks_attribute_writers
    a = DMP::Options.new
    b = DMP::Options.new

    b.diff_edit_cost = 5

    refute_equal a, b

    a.diff_edit_cost = 5

    assert_equal a, b
  end

  def test_equality_compares_values_numerically
    # Values are compared with ==, so an Integer equals the same-valued Float.
    assert_equal DMP::Options.new(diff_timeout: 1.0), DMP::Options.new(diff_timeout: 1)
  end

  def test_not_equal_to_non_options
    options = DMP::Options.new

    # A Hash with identical contents is still not an Options.
    refute_equal options, options.to_h

    # Objects without to_h compare unequal rather than raising.
    refute_equal options, nil
    refute_equal options, 'options'
  end

  def test_equal_options_are_the_same_hash_key
    a = DMP::Options.new(**OVERRIDES)
    b = DMP::Options.new(**OVERRIDES)

    assert_operator a, :eql?, b
    assert_equal a.hash, b.hash
    assert_equal :found, { a => :found }[b]
    assert_equal [a], [a, b].uniq

    # The frozen shared instance can be hashed and looked up too.
    assert_equal :found, { DMP::DEFAULT_OPTIONS => :found }[DMP::Options.new]
  end

  def test_not_eql_when_any_single_attribute_differs
    OVERRIDES.each do |name, value|
      a = DMP::Options.new
      b = DMP::Options.new(name => value)

      refute_operator a, :eql?, b, "#{name} should affect eql?"
      assert_nil({ a => :found }[b], "#{name} should affect the hash key")
    end
  end

  def test_eql_is_stricter_than_equality_for_numeric_types
    # Like Hash#eql?, an Integer and the same-valued Float are == but not eql?.
    int = DMP::Options.new(diff_timeout: 1)
    float = DMP::Options.new(diff_timeout: 1.0)

    assert_equal int, float
    refute_operator int, :eql?, float
    assert_equal 2, [int, float].uniq.size
  end

  def test_not_eql_to_non_options
    options = DMP::Options.new

    refute_operator options, :eql?, options.to_h
    refute_operator options, :eql?, nil
    refute_operator options, :eql?, 'options'
  end

  def test_default_options_definitely_frozen
    assert_predicate DMP::DEFAULT_OPTIONS, :frozen?
  end
end
