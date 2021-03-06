require 'forwardable'

module Coalesce

  class Batch
    attr_reader :objects
    attr_reader :combiners
    attr_reader :locks
    attr_reader :rules_matched

    extend Forwardable
    def_delegators :@objects, :[], :size, :first, :last, :each, :empty?

    include Enumerable

    def initialize(prototype)
      @objects       = [prototype]
      @combiners     = []
      @locks         = []
      @rules_matched = []
    end

    def prototype
      @objects.first
    end

    def add_object(object)
      @objects.push(object)
    end

    def add_combiner(combiner)
      @combiners.push(combiner) unless @combiners.include?(combiner)
    end

    def lock(name)
      @locks.push(name) unless @locks.include?(name)
    end

    def unlock(name)
      @locks.delete(name)
    end

    # This makes a duplicate of the prototype, then starts replacing attributes
    # with the result of the combiners.
    def to_standin
      combined = {}
      @combiners.each do |combiner|
        aggregate = @objects.map do |object|
          if object.respond_to?(combiner.attribute)
            object.send(combiner.attribute)
          else
            nil
          end
        end
        combined[combiner.attribute] = combiner.call(aggregate)
      end

      # We'd like to dup or clone the prototype object to not modify the
      # original, but some ORMs, ActiveRecord included, override dup to
      # clear id, created_at timestamps, etc, making the returned object
      # less like the original than we'd like.
      object = prototype

      # Give us access to self as batch in the context of the new methods
      tap do |batch|
        object.define_singleton_method(:batch) do
          batch
        end

        object.define_singleton_method(:combined_attributes) do
          combined
        end

        object.define_singleton_method(:combined?) do |k=nil|
          k ? combined.key?(k) : !combined.empty?
        end

        combined.each do |k, v|
          object.define_singleton_method(k) do
            v
          end
        end
      end

      object
    end
  end

end
