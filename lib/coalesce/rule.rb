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

    # Adds a custom predicate rule, which gets passed |block, candidate|.
    # It should return true if the candidate can be added to the batch,
    # otherwise false.
    def predicate!(&block)
      @predicates.push(block)
      nil
    end

    # Returns true if the candidate has an attribute named "attr_name", and
    # its value is in "values"
    def attr_in(attr_name, *values)
      predicate! do |batch, candidate|
        candidate.respond_to?(attr_name) &&
          values.include?(candidate.send(attr_name))
      end
    end

    # Evaluates to true if:
    #  * The candidate has an attribute named "key"
    #  * The candidate's key attribute value is in the list of key_values
    #  * The candidate's key attribute value matches the batch, in terms of
    #    same(:key, as: as).  as: defaults to :all
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

    # Generates a predicate for each value in keys.
    # The generated predicate compares the candidate's attribute value given
    # by :key to the batch, according to the value of :as
    #
    # :as values
    #   :all [default] : candidate.send(key) must match the result from every
    #                    object in the batch.
    #   :any           : candidate.send(key) must match a result from any
    #                    object in the batch.
    #   :first         : candidate.send(key) is compared to the first object
    #                    in the batch
    #   :last          : candidate.send(key) is compared to the last object
    #                    in the batch.
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

    # Compares a candidate's created_at value (or other, by providing :method)
    # to the batch.  By default, the candidate's timestamp is compared to the
    # first item in the batch, but "from :last" can be specified to keep a
    # "running timeout", which compares the candidate's timestamp to the last
    # item in the batch.
    def time_delta(delta, from: :first, method: :created_at)
      unless [:first, :last].include?(from)
        fail ArgumentError, ':from must be one of :first or :last'
      end

      predicate! do |batch, candidate|
        target = batch.objects.send(from)
        candidate.send(method) - target.send(method) <= delta
      end
    end

    # Marks the batch as "locked" to "rule_names".  Only rules that are in
    # rule_names will be tested for matches until they are unlocked.
    # Lock ADDS TO the locked rule names, doesn't replace them.
    #
    # rule_names defaults to the current rule's name.
    def lock(*rule_names)
      @locks += rule_names.empty? ? [name] : rule_names
    end

    # Unlocks a batch. see: lock
    def unlock(*rule_names)
      @unlocks += rule_names.empty? ? [name] : rule_names
    end

    # Adds one or more combiners to the batch.
    #
    # A combiner is added for each attr_name, with options specified by
    # any keyword options, or a block.
    def combine(*attr_names, **kw, &block)
      intersection = @combiners.map(&:attribute) & attr_names

      unless intersection.empty?
        fail ArgumentError, "duplicate attributes #{intersection.inspect}"
      end

      @combiners += Combiner.build_list(*attr_names, **kw, &block)
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