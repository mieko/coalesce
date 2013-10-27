module Coalesce
  class Combiners
    # No-op
    def none(values)
      values
    end

    def array(values, unique: false, singular: false)
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
    def smart_key(values)
      parts = values.map { |v| v.split '.' }
      len = parts.max_by(&:size).size

      (0...len).map do |seg|
        to_combine = parts.map { |p| p[seg] }.compact
        to_combine.sort.uniq.join('_')
      end.join('.')
    end

    def hash_merge(values, method: :reverse_merge)
      values.inject({}, method)
    end

    def hash_merge_array(values,
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
    def only_except(k, only, except, predicate_value: nil)
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