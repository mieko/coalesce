module Coalesce
  class Grouper
    attr_accessor :enabled
    attr_reader   :rules
    attr_reader   :combiners

    def initialize(enabled: true, &proc)
      @enabled   = enabled
      @rules     = []
      @combiners = []
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
              rule.apply!(batch, candidate)
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