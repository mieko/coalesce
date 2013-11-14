module Coalesce
  class Grouper
    attr_accessor :enabled
    attr_reader   :items
    attr_reader   :rules
    attr_reader   :combiners

    def initialize(enabled: true, &proc)
      @enabled   = enabled
      @rules     = []
      @combiners = []
      @lines     = nil

      instance_exec(&proc) if proc
    end

    def rule(*args, &proc)
      @rules.push(Rule.new(*args, &proc))
    end

    def combine(*args, **kw)
      @combiners += Combiner.build_list(*args, **kw)
    end

    def each(items, &proc)
      return enum_for(__method__, items) unless block_given?
      return items.each(&proc) if !@enabled

      batch = nil

      iterator = items.each
      candidate = iterator.next

      loop do
        catch (:process_next) do
          if batch.nil?
            batch = Batch.new(candidate)
            candidate = iterator.next
            throw :process_next
          end

          rules.each do |rule|
            if rule.matches?(batch, candidate)
              batch.add_object(candidate)
              rule.combiners.each { |c| batch.add_combiner(c) }
              candidate = iterator.next
              throw :process_next
            end
          end

          yield batch.to_standin
          batch = nil
        end
      end

      yield batch.to_standin unless batch.nil?

    end
  end
end