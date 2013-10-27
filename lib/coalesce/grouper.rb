module Coalesce
  class Grouper
    attr_accessor :enabled
    attr_reader   :items

    def initialize(enabled: true)
      @enabled   = enabled
      @rules     = []
      @configure = -> (batch) {}
      @lines     = nil
    end

    def rule(*args, &proc)
      rules.push(Rule.new(*args, &proc))
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
        batch = Batch.new(candidate, @rules) and next if batch.nil?
        @configure.(batch)

        next if batch.combine!(candidate)
        batch.results.each {|r| yield r }

        returned += 1
        break if @lines && returned == @lines - 1

        batch = Batch.new(candidate, @rules)
        @configure.(batch)
      end
      # use find_each if possible, each otherwise
      items.send(items.respond_to?(:find_each) ? :find_each : :each, &over_each)

      batch.results.each {|r| yield r } unless batch.nil?
    end

    def rule(*args, **kwargs, &predicate)
      @rules << Rule.new(*args, **kwargs, &predicate)
    end

  end
end