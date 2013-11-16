module Coalesce

  class RuleDSL
    attr_reader :name
    attr_reader :predicates
    attr_reader :locks, :unlocks
    attr_reader :combiners

    def initialize(name, &block)
      @name       = name
      @predicates = []
      @locks      = []
      @unlocks    = []
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
          values.include?(candidate.send(attr_name))
      end
    end

    def key(*key_values, as: :all)
      attr_in(:key, *key_values)
      same(:key, as: as)
    end

    def suspend
    end

    def batch_key(*key_values)
      predicate! do |batch, candidate|
        key_values.include?(batch.prototype.key)
      end
    end

    def same(*keys, as: :all)
      unless %i(any all first last).include?(as)
        fail ArgumentError, ':as must be one of :any, :all, :first, or :last'
      end

      keys.each do |key|
        predicate! do |batch, candidate|
          pred = ->(obj) do
            obj.respond_to?(key) && candidate.respond_to?(key) &&
            candidate.send(key) == obj.send(key)
          end
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

    def lock(*rule_names)
      @locks += rule_names.empty? ? [name] : rule_names
    end

    def unlock(*rule_names)
      @unlocks = @unlocks - rule_names
    end

    def combine(*attr_names, **kw)
      @combiners += Combiner.build_list(*attr_names, **kw)
    end
  end


  class Rule
    attr_reader :name, :predicates, :locks, :unlocks, :combiners

    def initialize(name, &block)
      dsl = RuleDSL.new(name, &block)

      @name, @predicates, @locks, @unlocks, @combiners =
        dsl.name, dsl.predicates, dsl.locks, dsl.unlocks, dsl.combiners
    end

    def matches?(batch, candidate)
      if !batch.locks.empty?
        return false unless batch.locks.include?(name)
      end

      @predicates.all? {|p| p.(batch, candidate)}
    end

    def apply!(batch, candidate)
      unless batch.rules_matched.include?(self)
        batch.rules_matched.push(self)

        locks.each     { |l| batch.lock(l)         }
        unlocks.each   { |l| batch.unlock(l)       }
        combiners.each { |c| batch.add_combiner(c) }
      end

      batch.add_object(candidate)
    end

  end
end