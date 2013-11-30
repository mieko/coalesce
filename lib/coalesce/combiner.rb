module Coalesce
  class Combiner
    attr_reader :attribute, :with, :options, :compact

    def initialize(attribute, with: nil, compact: true, **options, &block)
      if with && block
        fail ArgumentError, 'cannot provide both :with and block'
      end

      # default to the block if given, or :array
      @with = with || block || :array
      @attribute, @options, @compact = attribute, options, compact
    end

    def self.build_list(*attr_names, **kw, &block)
      attr_names.map do |attr_name|
        new(attr_name, **kw, &block)
      end
    end

    def call(values)
      callable = with.respond_to?(:call) ? with : self.class.method(with)
      values = values.compact if compact
      options.empty? ? callable.call(values) : callable.call(values, **options)
    end

    # The simplest combiner: adds all values to an array.
    # if :unique is true, it removes duplicates.
    # if :singular is true, AND the result has only one item,
    #   it will return the one item, not a one-element array containing
    #   the item.
    def self.array(values, unique: false, singular: false)
      values = values.uniq if unique
      if singular && values.size == 1
        values.first
      else
        values
      end
    end

    # This does the clever
    #  ['ticket.accept', 'ticket.close'] -> 'ticket.accept_close'
    # thing that makes PublicActivity happy
    def self.smart_key(values)
      parts = values.map { |v| v.split '.' }
      len = parts.max_by(&:size).size

      (0...len).map do |seg|
        to_combine = parts.map { |p| p[seg] }.compact
        to_combine.sort.uniq.join('_')
      end.join('.')
    end

    # To be used on an array of hashes.  Merges them left-to-right, using
    # :method, which defaults to :merge
    def self.hash_merge(values, method: :merge)
      values.inject({}, method)
    end

    # Selects the first element of the array
    def self.first(values)
      values.first
    end

    # Selects the last element of the array
    def self.last(values)
      values.last
    end

    # Selects the nth value of the array, given by :index
    def self.nth(values, index: nil)
      fail ArgumentError, ':index argument required' if index.nil?
      values[index]
    end

    # Returns a literal value, ignoring the array.  Specify the value to be
    # return with :value
    def self.literal(values, value: (fail ArgumentError, ':value required'))
      value.respond_to?(:dup) ? value.dup : value
    end

    # Merges an array of hashes into arrays for each value.  By default, all
    # keys are processed, but these can be limited with :only and :except.
    #
    # Keys that are processed are combined with :combiner, passing
    # :combiner_options.  Keys that are NOT processed will be processed with
    # :other, passing :other_options.
    def self.hash_merge_array(values,
                              only: nil,
                              except: nil,
                              combiner: :array,
                              combiner_options: {},
                              other: :first,
                              other_options: {})
      return values if values.size < 2

      result = {}

      values.each do |hash|
        hash.each do |k, v|
          result[k] ||= []
          result[k].push(v)
        end
      end

      kv = result.map do |k, v|
        if only_except(k, only, except)
          [k, send_ignoring_kw(combiner, v, **combiner_options)]
        else
          [k, send_ignoring_kw(other, v, **other_options)]
        end
      end
      Hash[kv]
    end

    private
    # Same as send(method, values, **kw), except in the case kw is
    # empty, they are not sent to method avoid ArgumentError
    def self.send_ignoring_kw(method, values, **kw)
      kw.empty? ? send(method, values) : send(method, values, **kw)
    end

    def self.only_except(k, only, except, predicate_value: nil)
      if only && except
        fail ArgumentError, 'only pass one of :only or :except'
      end

      return only.call(predicate_value)    if only.respond_to?(:call)
      return !except.call(predicate_value) if except.respond_to?(:call)

      return false if only   && !Array(only).include?(k)
      return false if except && Array(except).include?(k)
      return true
    end
  end
end
