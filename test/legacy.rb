# This is the terrible old, hacked-together ActivityGrouper that coalesce
# was meant to replace.  Obviously, it grew unweildy, and wasn't too flexible.
#
# However, because we have a lot of existing PublicActivity views which depend
# on its behaviour, I needed to ensure that coalesce CAN express the rules, and
# generate the same results as ActivityGrouper
#
# When all these tests pass, this file, legacy_test.rb, and legacy.csv can be
# removed from source control.

module Legacy

  class CombineRule
    attr_accessor :key, :combine, :same, :uniq, :lock, :time_delta, :merge,
                  :suspended, :predicate

    # key:        String.  shortcut for same: [:key] and a predicate that
    #             compares the key to this string.
    # combine:    Symbol or array of symbols.
    #             When a rule matches, the attributes passed through :combine
    #             are collected in the result attribute.  By default, the result
    #             will turn from a scalar into an array.  If the attribute is in
    #             :merge as well, instead a hash merge will occur.
    #
    #             There is a special case for the attribute "key", which follows
    #             an algorithm meant to be convenient for PublicActivity, for
    #             example:
    #              'ticket.create' + 'ticket.accept' => 'ticket.accept_create'
    #              'comment.create' + 'ticket.close' =>
    #                'comment_ticket.close_create'
    #             Note that each dot-seperated segment is sorted alphabetically.
    # same:       Symbol or array of symbols.
    #             Rule is only matched if the candidate and ALL objects already
    #             in the batch give the same result when EVERY method name in
    #             :same is called.
    # uniq:       Symbol or array of symbols
    #             Attribute names given in :uniq must also be present in
    #             :combine.
    #             When generating a combined result, these attributes are only
    #             appended to the array if they are not already present,
    #             preventing duplicates
    # lock:       Boolean.  If this rule matches, the batch will only look at
    #             this rule for future merges.
    # time_delta: Rule is only processed if the candidate object is within
    #             time_delta of the prototype (first) object.
    # merge:      Symbol or array of symbols.
    #             see :combine above.  All values in :merge must also be in
    #             :combine
    # suspended:  If this rule matches, further rule processing will still
    #             occur, but unless the batch ALSO matches another rule, it'll
    #             be "backed out" in the results.  This lets you catch rules
    #             like 'ticket.accept' + 'comment.create' + 'ticket.close' by
    #             matching 'ticket.accept' + 'comment.create' with
    #             suspended: true to continue rule processing, and catching
    #             'ticket.accept' + 'comment.create' and 'ticket.close' later.
    #             If the latter rule never triggers, the batch will just return
    #             the first two activities as normal.

    def initialize(key: nil, combine: nil, same: nil, uniq: nil, lock: false,
                   time_delta: nil, merge: nil, suspended: false,
                   &predicate)
      @key        = key
      @combine    = Array(combine)
      @same       = Array(same)
      @uniq       = Array(uniq)
      @merge      = Array(merge)
      @predicate  = predicate || ->(l, r, *extra) { true }
      @time_delta = time_delta
      @lock       = lock
      @suspended  = suspended

      raise ArgumentError, "All values in :uniq must also be in :combine" \
            unless (@uniq - @combine).empty?
      raise ArgumentError, "All values in :merge must also be in :combine" \
            unless (@merge - @combine).empty?
    end

    def close_enough?(batch, r)
      return true if @time_delta.nil?
      return r.created_at - batch.prototype.created_at <= @time_delta
    end

    def key_match?(batch, r)
      return true if @key.nil?
      return true if batch.prototype.key == @key && r.key == @key
      return false
    end

    def should_combine?(batch, r)
      return false unless close_enough?(batch, r)
      return false unless key_match?(batch, r)

      @same.each do |method|
        return false unless r.respond_to?(method)
        rval = r.send(method)
        return false unless batch.objects.all? {|act| act.respond_to?(method) &&
                                                      act.send(method) == rval }
      end
      @predicate.(batch, r)
    end
  end

  class BatchedActivity
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

    def close_enough?(r)
      return true if @max_time_delta.nil?
      return r.created_at - prototype.created_at <= @max_time_delta
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

    def combined_key_name(keys)
      parts = keys.map{|k| k.split '.'}
      len = parts.max_by(&:size).size

      (0...len).map do |seg|
        to_combine = parts.map{|p| p[seg]}.reject(&:nil?)
        to_combine.sort.uniq.join('_')
      end.join('.')
    end

    def replace_attr(obj, attr, val)
      obj.define_singleton_method(attr) do
        val
      end
    end

  end


  class ActivityGrouper
    attr_accessor :enabled
    attr_reader   :items

    def initialize(enabled: true)
      @enabled   = enabled
      @rules     = []
      @configure = -> (batch) {}
      @lines     = nil
    end

    def configure_batch(&proc)
      @configure = proc
    end

    def each(items, &proc)
      return enum_for(:each, items) unless block_given?
      items.each(&proc) and return if !@enabled

      batch = nil
      returned = 0

      over_each = ->(candidate) do
        batch = BatchedActivity.new(candidate, @rules) and next if batch.nil?
        @configure.(batch)

        next if batch.combine!(candidate)
        batch.results.each {|r| yield r }

        returned += 1
        break if @lines && returned == @lines - 1

        batch = BatchedActivity.new(candidate, @rules)
        @configure.(batch)
      end
      # use find_each if possible, each otherwise
      items.send(items.respond_to?(:find_each) ? :find_each : :each, &over_each)

      batch.results.each {|r| yield r } unless batch.nil?
    end

    def rule(*args, **kwargs, &predicate)
      @rules << CombineRule.new(*args, **kwargs, &predicate)
    end

  end

end