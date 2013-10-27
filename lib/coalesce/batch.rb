require 'forwardable'

module Coalesce

  class Batch
    attr_reader :objects
    attr_reader :locks

    extend Forwardable
    def_delegators :@objects, :[], :size, :first, :last, :each, :empty?

    include Enumerable

    def initialize(prototype)
      @objects = [prototype]
      @locks = []
    end

    def prototype
      @objects.first
    end
  end

  class Batch2
    attr_reader   :rules, :prototype, :keys, :objects
    attr_accessor :max_time_delta
    attr_reader   :locked_rule

    def initialize(prototype, rules)
      @prototype = prototype
      @rules = rules
      @locked_rule = nil
      @keys = {}
      @objects = [@prototype]
      @suspended = false
      initialize_combinable!
    end

    include Enumerable
    def each(&proc)
      return onjects.each(&proc)
    end

    def should_combine?(r)
      return nil unless close_enough?(r)
      if @locked_rule
        return nil unless @locked_rule.should_combine?(self, r)
        @locked_rule
      else
        @rules.find {|rule| rule.should_combine?(self, r) }
      end
    end

    def lock!
      @locked_rule = -> (*args) { false }
    end

    def combine!(r)
      if rule = should_combine?(r)
        update_combine_hash!(rule, r)
        @locked_rule = rule if rule.lock
        @suspended = rule.suspended
        @objects.push(r)
        true
      else
        false
      end
    end

    def results
      return @objects if @suspended

      obj = @prototype.clone
      append_combine_hash!(@keys, obj)
      return [obj]
    end

    def all_share_the_same?(attr)
      @objects.map(&(attr.to_proc)).sort.uniq == [attr]
    end

    private
    def initialize_combinable!
      @rules.each do |rule|
        rule.combine.each do |comb|
          keys[comb] = []
          result = @prototype.respond_to?(comb) ? @prototype.send(comb) : nil
          keys[comb].push(result) unless result.nil?
        end
      end
    end

    def update_combine_hash!(rule, r)
      rule.combine.each do |comb|
        if r.respond_to?(comb)
          result = r.send(comb)
          @keys[comb].push(result) unless \
            rule.uniq.include?(comb) && @keys[comb].include?(result)
          @keys[comb] = [@keys[comb].inject(&:merge)] if \
            rule.merge.include?(comb)
        end
      end
    end

    def append_combine_hash!(hash, obj)
      replace_attr(obj, :combined?, true)
      replace_attr(obj, :batch, self)

      hash.each do |k, v|
        if k == :key
          replace_attr(obj, k, combined_key_name(v))
        else
          replace_attr(obj, k, v.size == 1 ? v.first : v)
        end
      end
    end

    def replace_attr(obj, attr, val)
      obj.define_singleton_method(attr) do
        val
      end
    end

  end
end
