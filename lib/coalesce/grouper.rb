module Coalesce
  class Grouper
    attr_accessor :enabled
    attr_reader   :rules

    def initialize(enabled: true, &proc)
      @enabled   = enabled
      @rules     = []

      instance_exec(&proc) if proc
    end

    def rule(name, *args, &proc)
      if @rules.any? {|r| r.name == name}
        fail ArgumentError, "duplicate rule name: #{name.inspect}"
      end

      @rules.push(Rule.new(name, *args, &proc))
    end

    def each(items, &proc)
      return enum_for(__method__, items) unless block_given?

      iterator = enumerator_for(items)

      # If we're not enabled, just delegate to the collection
      return iterator.each(&proc) if !enabled

      buffer = []
      next_candidate = -> do
        return buffer.pop unless buffer.empty?
        return iterator.next
      end

      rollback = -> (batch) do
        buffer = buffer + batch.objects.reverse
      end

      batch = nil
      candidate = next_candidate.call

      loop do
        catch (:process_next) do
          if batch.nil?
            batch = Batch.new(candidate)
            candidate = next_candidate.call
            throw :process_next
          end

          rules.each do |rule|
            if rule.matches?(batch, candidate)
              rule.apply!(batch, candidate)
              candidate = next_candidate.call
              throw :process_next
            end
          end

          yield batch.to_standin
          batch = nil
        end
      end

      yield batch.to_standin unless batch.nil?
    end

    private

    def first_rule_that_matches(batch, object)
      rules.detect do |rule|
        rule.matches?(batch, object)
      end
    end

    def consume_all_matches(batch, collection)
      fail RuntimeError, "batch wasnt empty" unless batch.empty?

      rule = first_rule_that_matches(batch, object)
      return 0 if rule.nil?

      if rule.sequential?
        consume_all_matches_sequential(rule, batch, collection)
      else
        consume_all_matches_random_access(rule, batch, collection)
      end
    end

    def consume_all_matches_sequential(rule, batch, collection)
    end

    def enumerator_for(collection)
      # Until very recently, ActiveRecord's find_each didn't return an
      # Enumerator.  This should work for new and old releases, and any other
      # object that implements similar behaviour.
      #
      # https://github.com/rails/rails/pull/10992

      if collection.respond_to?(:find_each)
        collection.enum_for(:find_each)
      elsif collection.respond_to?(:each)
        # Yet we still don't want to encourage the behaviour, so we expect
        # each to do the enum_for thing.
        collection.each
      else
        fail ArgumentError, "collection is not enumerable"
      end
    end

  end
end