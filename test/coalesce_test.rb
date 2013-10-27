require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'ostruct'
require 'active_support/core_ext'

require 'coalesce'


class Activity < OpenStruct

end

class CoaleseTest < MiniTest::Unit::TestCase
  include Coalesce

  def setup
  end

  def teardown
  end

  def test_tests
    assert_equal true, true
  end

  def test_combiners_smart_key
    c = Combiners.new
    assert_equal 'ticket.accept_close',
                 c.smart_key(['ticket.accept', 'ticket.close'])

    assert_equal 'comment_ticket.create',
                 c.smart_key(['ticket.create', 'comment.create'])
  end

  def test_combiners_array
    c = Combiners.new
    assert_equal ['Mike', 'Tucson'],
                 c.array(['Mike', 'Tucson'])

    assert_equal ['Mike', 'Tucson', 'Mike'],
                 c.array(['Mike', 'Tucson', 'Mike'])

    assert_equal ['Mike', 'Tucson'],
                 c.array(['Mike', 'Tucson', 'Mike'], unique: true)

    assert_equal 'Mike', c.array(['Mike'], singular: true)
    assert_equal ['Mike'], c.array(['Mike'], singular: false)

    assert_equal 'Mike',
                 c.array(['Mike', 'Mike'], unique: true, singular: true)
  end

  def test_combiners_hash_merge
    c = Combiners.new
    left  = {name: 'Mike', age: 901, pet: 'Tucson'}
    right = {name: 'Bob',  age: 109, car: 'Dodge' }
    result = c.hash_merge([left, right])

    assert_equal 'Mike',   result[:name]
    assert_equal 901,      result[:age]
    assert_equal 'Tucson', result[:pet]
    assert_equal 'Dodge',  result[:car]

    result = c.hash_merge([left, right], method: :merge)
    assert_equal 'Bob',    result[:name]
    assert_equal  109,     result[:age]
    assert_equal 'Tucson', result[:pet]
    assert_equal 'Dodge',  result[:car]
  end

  def test_combiners_hash_merge_array
    c = Combiners.new
    p1 = {name: 'Mike', pet: 'Tucson'}
    p2 = {name: 'Bob',  pet: 'Izzie'}

    result = c.hash_merge_array([p1, p2])
    assert_equal ['Mike', 'Bob'], result[:name]
    assert_equal ['Tucson', 'Izzie'], result[:pet]


    p1 = {name: 'Mike', pet: 'Tucson'}
    p2 = {name: 'Mike', pet: 'Trollface'}

    result = c.hash_merge_array([p1, p2], only: :pet, other: :first)
    assert_equal 'Mike', result[:name]
    assert_equal ['Tucson', 'Trollface'], result[:pet]


    p1 = {name: 'Mike', pet: 'Tucson'}
    p2 = {name: 'Bob',  pet: 'Trollface'}

    result = c.hash_merge_array([p1, p2], only: :pet, other: :last)
    assert_equal 'Bob', result[:name]
    assert_equal ['Tucson', 'Trollface'], result[:pet]
  end

  def test_rule
    epoch = Time.now
    activities = [
      Activity.new(key: 'ticket.accept',  ticket: 1, owner: 'Mike', created_at: epoch - 10.minutes),
      Activity.new(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch - 9.minutes),
      Activity.new(key: 'ticket.comment', ticket: 1, owner: 'Mike', created_at: epoch - 8.minutes),
      Activity.new(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch - 7.minutes),
    ]

    grouper = Grouper.new do
      rule 'ticket.close_accept' do
        key  'ticket.accept', 'ticket.close'
        same :ticket
        same :owner
        time_delta 1.minute, from: :first

        combine :key,    with: :smart_key
        combine :ticket, with: :array, unique: true
        combine :owner,  with: :array
      end
    end

    grouper.each(activities) do |act|
    end

    # batch = Batch.new(activities.first)
    # assert_equal true,  rule.matches?(batch, activities[1])
    # assert_equal false, rule.matches?(batch, activities[2]) # wrong key
    # assert_equal false, rule.matches?(batch, activities[3]) # too late
  end

end