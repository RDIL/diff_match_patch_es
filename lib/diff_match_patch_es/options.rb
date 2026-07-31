# frozen_string_literal: true

module DiffMatchPatchES
  class Options
    ATTRIBUTES = %i[
      diff_timeout
      diff_edit_cost
      match_threshold
      match_distance
      patch_delete_threshold
      patch_margin
      match_max_bits
    ].freeze

    attr_accessor(*ATTRIBUTES)

    def initialize(
      diff_timeout: 1.0,
      diff_edit_cost: 4,
      match_threshold: 0.5,
      match_distance: 1000,
      patch_delete_threshold: 0.5,
      patch_margin: 4,
      match_max_bits: 32
    )
      @diff_timeout = diff_timeout
      @diff_edit_cost = diff_edit_cost
      @match_threshold = match_threshold
      @match_distance = match_distance
      @patch_delete_threshold = patch_delete_threshold
      @patch_margin = patch_margin
      @match_max_bits = match_max_bits
    end

    def to_h
      ATTRIBUTES.to_h { |name| [name, public_send(name)] }
    end

    def ==(other)
      other.is_a?(Options) && to_h == other.to_h
    end
  end

  DEFAULT_OPTIONS = Options.new.freeze

  module_function

  # Accepts nil, a Hash of overrides, or an already-resolved Options.
  def resolve_options(options = nil)
    case options
    when Options then options
    when nil then Options.new
    when Hash then Options.new(**options)
    else
      raise ArgumentError, "Unsupported options: #{options.inspect}"
    end
  end
end
