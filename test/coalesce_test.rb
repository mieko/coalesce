require 'delegate'
require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'active_support/core_ext'

require_relative './test_models'

require 'coalesce'

class CoaleseTest < MiniTest::Unit::TestCase
  include Coalesce

  def a!(*args, **kw)
    Activity.new(*args, **kw)
  end

  def epoch
    @epoch ||= Time.now
  end

  def test_batch_object
    ticket_create  = a!(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch)
    ticket_comment = a!(key: 'ticket.comment', ticket: 1, owner: 'Mike', created_at: epoch + 1.minute)

    b = Batch.new(ticket_create)
    b.add_object(ticket_comment)
    b.add_combiner(Combiner.new(:key, with: :smart_key))
    b.add_combiner(Combiner.new(:ticket, unique: true, singular: true))
    b.add_combiner(Combiner.new(:owner))

    result = b.to_standin

    assert_equal %i(key ticket owner).sort, result.combined_attributes.keys.sort

    assert result.combined?
    assert result.combined?(:key)
    assert result.combined?(:ticket)
    assert result.combined?(:owner)
    refute result.combined?(:created_at)

    assert_equal 'ticket.close_comment', result.key
    assert_equal 1, result.ticket
    assert_equal ['Mike', 'Mike'], result.owner
    assert_equal epoch, result.created_at
  end


  def test_grouper_simple
    activities = [
      a!(id: 1, key: 'ticket.create', owner: 'Mike Owens'),
      a!(id: 1, key: 'ticket.notify', owner: 'Mike Owens', extra: {recipient: 'Joe'}),
      a!(id: 1, key: 'ticket.notify', owner: 'Mike Owens', extra: {recipient: 'Matt'})
    ]

    g = Grouper.new(enabled: true) do
      rule 'ticket.create_notify' do
        key 'ticket.notify'
        same :id, :key, :owner

        combine :id,    unique: true, singular: true
        combine :owner, unique: true, singular: true
        combine :extra, with: :hash_merge_array
      end
    end

    result = g.each(activities).to_a

    assert_equal 2,     result.size
    assert_equal false, result[0].combined?
    assert_equal true,  result[1].combined?

    assert_equal 1, result[1].id
    assert_equal 'Mike Owens', result[1].owner
    assert_equal ['Joe', 'Matt'], result[1].extra[:recipient]
  end

  def test_grouper_locks
    activities = [
      a!(id: 1, name: 'Mike', age: 99),
      a!(id: 1, name: 'Bob',  age: 99),
      a!(id: 1, name: 'Leah', age: 99)
    ]

    g = Grouper.new do
      rule :one do
        same :id

        lock :never
        combine :name
      end

      rule :two do
        same :age

        lock
        combine :age
      end
    end

    result = g.each(activities).to_a

    assert_equal 2, result.size
  end

  def test_grouper_disable
    activities = [
      a!(id: 1, name: 'Bob'),
      a!(id: 1, name: 'Bobberson')
    ]

    g = Grouper.new(enabled: false) do
      rule :combine_by_id do
        same :id
        combine :id
      end
    end

    results = g.each(activities).to_a
    assert_equal 2, results.size

    g.enabled = true
    results = g.each(activities).to_a
    assert_equal 1, results.size
  end

  def test_grouper_chain
    activities = [
      a!(key: 'ticket.accept',  id: 1, user: 2),
      a!(key: 'ticket.comment', id: 1, user: 2),
      a!(key: 'ticket.close',   id: 1, user: 2)
    ]

    g = Grouper.new do
      rule :accept_and_close do
        same  :id, :user
        chain :key, 'ticket.accept', 'ticket.comment', :'*', 'ticket.close'

        lock
        combine :key, with: :smart_key
        combine :id,   singular: true, unique: true
        combine :user, singular: true, unique: true
      end
    end

    results = g.each(activities).to_a
    assert_equal 1, results.size
    assert_equal 'ticket.accept_close_comment', results.first.key
    assert_equal 1, results.first.id
    assert_equal 2, results.first.user
  end

  # Simulates ActiveRecord's find_each, which, in released versions,
  # does not return an Enumerator when no block is specified.
  class StupidArray < SimpleDelegator
    def initialize(obj)
      super
    end

    def find_each
      each do |v|
        yield v
      end
    end
  end


  def test_grouper_find_each_patch
    activities = StupidArray.new [
      a!(id: 1, value: 'Mike'),
      a!(id: 1, value: 'Tucson')
    ]

    g = Grouper.new do
      rule :combine_by_id do
        same    :id
        combine :value
        combine :id, unique: true, singular: true
      end
    end

    result = g.each(activities).to_a
    assert_equal 1, result.size
    assert_equal 1, result.first.id
    assert_equal ['Mike', 'Tucson'], result.first.value
  end

end