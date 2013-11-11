module Coalesce
  class Combiner
    attr_reader :attribute, :with, :options

    def initialize(attribute, with: :array, **options)
      @attribute, @with, @options = attribute, with, options
    end

    def self.build_list(*attr_names, with: :array, **kw)
      attr_names.map do |attr_name|
        new(attr_name, with: with, options: kw)
      end
    end

    def call(values)
      if self.class.method(@with).parameters.size == 1
        self.class.send(@with, values)
      else
        self.class.send(@with, values, **@options)
      end
    end

    # No-op
    def self.none(values)
      values
    end

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

    def self.hash_merge(values, method: :reverse_merge)
      values.inject({}, method)
    end

    def self.first(values)
      values.first
    end

    def self.last(values)
      values.last
    end

    def self.literal(values, value: :_!)
      fail ArgumentError, ":value is required" if value == :_!
      value.respond_to?(:dup) ? value.dup : value
    end

    def self.nth(values, index: nil)
      fail ArgumentError, ":index argument required" if index.nil?
      values[index]
    end

    def self.hash_merge_array(values,
                              only: nil,
                              except: nil,
                              other: :first,
                              combiner: :array,
                              combiner_options: {})
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
          [k, send(combiner, v, **combiner_options)]
        else
          [k, v.send(other)]
        end
      end
      Hash[kv]
    end

    private
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