module Coalesce

  class RuleDSL
    attr_reader :predicates
    attr_reader :locks
    attr_reader :combiners

    def initialize(&block)
      @predicates = []
      @locks      = []
      @combiners  = []
      instance_exec(&block)
    end

    def predicate!(&block)
      @predicates.push(block)
      nil
    end

    def attr_in(attr_name, *values)
      predicate! do |batch, candidate|
        candidate.respond_to?(attr_name) &&
          Array(values).include?(candidate.send(attr_name))
      end
    end

    def key(*key_values)
      attr_in(:key, *key_values)
    end

    def batch_key(*key_values)
      predicate! do |batch, candidate|
        Array(key_values).include?(batch.prototype.key)
      end
    end

    def same(*keys, as: :all)
      unless [:any, :all, :first, :last].include?(as)
        fail ArgumentError, ':as must be one of :any, :all, :first, or :last'
      end

      Array(keys).each do |key|
        predicate! do |batch, candidate|
          pred = ->(obj) { candidate.send(key) == obj.send(key) }
          if [:any, :all].include?(as)
            batch.objects.send("#{as}?", &pred)
          else
            pred.call(batch.send(as))
          end
        end
      end
    end

    def time_delta(delta, from: :first, method: :created_at)
      unless [:first, :last].include?(from)
        fail ArgumentError, ':from must be one of :first or :last'
      end

      predicate! do |batch, candidate|
        target = batch.objects.send(from)
        candidate.send(method) - target.send(method) <= delta
      end
    end

    def lock_names(*rule_names)
      @locks += Array(rule_names)
    end

    def unlock_names(*rule_names)
      @locks = @locks - Array(rule_names)
    end

    def combine(*attr_names, with: :array, **kw)
      Array(attr_names).each do |attr|
        @combiners.push([attr, with, kw])
      end
    end
  end


  class Rule
    attr_reader :name

    def initialize(name, &block)
      dsl = RuleDSL.new(&block)
      @name = name
      @predicates, @locks = dsl.predicates, dsl.locks
    end

    def matches?(batch, candidate)
      return false if !batch.locks.empty? && !batch.locks.include?(name)
      @predicates.all? {|p| p.(batch, candidate)}
    end

    def apply(batch, candidate)
      batch.locks += @locks unless @locks.empty?
      @combiners.each do |combiner|
        combiner.call(batch, candidate)
      end
    end

    def call(batch, candidate)
      if matches?(batch, candidate)
        apply(batch, candidate)
        true
      else
        false
      end
    end
  end
end