require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'ostruct'
require 'active_support/core_ext'

require 'coalesce'


class Activity < OpenStruct
  def inspect
    s = each_pair.map {|k,v| "#{k}=#{send(k).inspect}"}.join ' '
    "\#<#{self.class.name} #{s}>"
  end
end

class CoaleseTest < MiniTest::Unit::TestCase
  include Coalesce

  def setup
  end

  def teardown
  end

  def epoch
    @epoch ||= Time.now
  end

  def test_combiners_smart_key
    assert_equal 'ticket.accept_close',
                 Combiner.smart_key(['ticket.accept', 'ticket.close'])

    assert_equal 'comment_ticket.create',
                 Combiner.smart_key(['ticket.create', 'comment.create'])
  end

  def test_combiners_position
    assert_equal 'Mike',   Combiner.first(['Mike', 'Tucson'])
    assert_equal 'Tucson', Combiner.last(['Mike', 'Tucson'])
    assert_equal 'Kayla',  Combiner.nth(['Mike', 'Kayla', 'Tucson'], index: 1)
  end

  def test_combiners_array
    assert_equal ['Mike', 'Tucson'],
                 Combiner.array(['Mike', 'Tucson'])

    assert_equal ['Mike', 'Tucson', 'Mike'],
                 Combiner.array(['Mike', 'Tucson', 'Mike'])

    assert_equal ['Mike', 'Tucson'],
                 Combiner.array(['Mike', 'Tucson', 'Mike'], unique: true)

    assert_equal 'Mike', Combiner.array(['Mike'], singular: true)
    assert_equal ['Mike'], Combiner.array(['Mike'], singular: false)

    assert_equal 'Mike',
                 Combiner.array(['Mike', 'Mike'], unique: true, singular: true)
  end

  def test_combiners_hash_merge
    left  = {name: 'Mike', age: 91, pet: 'Tucson'}
    right = {name: 'Bob',  age: 19, car: 'Dodge' }
    result = Combiner.hash_merge([left, right])

    assert_equal 'Mike',   result[:name]
    assert_equal 91,       result[:age]
    assert_equal 'Tucson', result[:pet]
    assert_equal 'Dodge',  result[:car]

    result = Combiner.hash_merge([left, right], method: :merge)
    assert_equal 'Bob',    result[:name]
    assert_equal 19,       result[:age]
    assert_equal 'Tucson', result[:pet]
    assert_equal 'Dodge',  result[:car]
  end

  def test_combiners_hash_merge_array
    p1 = {name: 'Mike', pet: 'Tucson'}
    p2 = {name: 'Bob',  pet: 'Izzie'}

    result = Combiner.hash_merge_array([p1, p2])
    assert_equal ['Mike', 'Bob'], result[:name]
    assert_equal ['Tucson', 'Izzie'], result[:pet]


    p1 = {name: 'Mike', pet: 'Tucson'}
    p2 = {name: 'Mike', pet: 'Trollface'}

    result = Combiner.hash_merge_array([p1, p2], only: :pet, other: :first)
    assert_equal 'Mike', result[:name]
    assert_equal ['Tucson', 'Trollface'], result[:pet]


    p1 = {name: 'Mike', pet: 'Tucson'}
    p2 = {name: 'Bob',  pet: 'Trollface'}

    result = Combiner.hash_merge_array([p1, p2], only: :pet, other: :last)
    assert_equal 'Bob', result[:name]
    assert_equal ['Tucson', 'Trollface'], result[:pet]
  end

  def test_combiners_literal
    assert_equal 'x', Combiner.literal(['I', 'am', 'awesome'], value: 'x')
    assert_equal [], Combiner.literal(['I', 'am', 'awesome'], value: [])
  end

  def test_combiner_object
    c = Combiner.new(:name, with: :array, unique: true)
    assert_equal ['Mike', 'Tucson'], c.call(['Mike', 'Tucson', 'Tucson'])

    c = Combiner.new(:key, with: :smart_key)
    assert_equal 'ticket.close_create', c.call(['ticket.create', 'ticket.close'])
  end

  def test_rule_dsl
    rule = Rule.new 'ticket.close_accept' do
      key  'ticket.accept', 'ticket.close'
      same :ticket
      same :owner
      time_delta 1.minute, from: :first

      combine :key,    with: :smart_key
      combine :ticket, with: :array, unique: true
      combine :owner,  with: :array
      combine :closer, :acceptor
    end
    assert_equal 'ticket.close_accept', rule.name
    assert_equal 4, rule.predicates.size
    assert_equal 5, rule.combiners.size
  end

  def a!(*args, **kw)
    Activity.new(*args, **kw)
  end

  def test_rule
    activities = [
      a!(key: 'ticket.accept',  ticket: 1, owner: 'Mike', created_at: epoch - 10.minutes),
      a!(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch - 9.minutes),
      a!(key: 'ticket.comment', ticket: 1, owner: 'Mike', created_at: epoch - 8.minutes),
      a!(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch - 7.minutes),
      a!(key: 'ticket.close',   ticket: 1, owner: 'Bob',  created_at: epoch - 7.minutes)
    ]

    rule = Rule.new('ticket.accept_close') do
      key 'ticket.accept', 'ticket.close'
      same :ticket, :owner
    end

    batch = Batch.new(activities.first)

    assert_equal true,  rule.matches?(batch, activities[0])
    assert_equal true,  rule.matches?(batch, activities[1])
    assert_equal false, rule.matches?(batch, activities[2])
    assert_equal true,  rule.matches?(batch, activities[3])
    assert_equal false, rule.matches?(batch, activities[4])
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

end