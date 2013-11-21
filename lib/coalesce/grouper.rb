module Coalesce
  class Grouper
    attr_accessor :enabled
    attr_reader   :rules

    def initialize(enabled: true, &proc)
      @enabled   = enabled
      @rules     = []
      @lines     = nil

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

      # Until very recently, ActiveRecord's find_each didn't return an
      # Enumerator.  This should work for new and old releases, and any other
      # object that implements similar behaviour.
      #
      # https://github.com/rails/rails/pull/10992
      iterator = if items.respond_to?(:find_each)
        items.enum_for(:find_each)
      else
        items.each
      end

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
  end
end