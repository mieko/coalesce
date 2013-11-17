require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'coalesce/combiner'

class CombinersTest < MiniTest::Unit::TestCase
  include Coalesce

  def test_smart_key
    assert_equal 'ticket.accept_close',
                 Combiner.smart_key(['ticket.accept', 'ticket.close'])

    assert_equal 'comment_ticket.create',
                 Combiner.smart_key(['ticket.create', 'comment.create'])
  end

  def test_position
    assert_equal 'Mike',   Combiner.first(['Mike', 'Tucson'])
    assert_equal 'Tucson', Combiner.last(['Mike', 'Tucson'])
    assert_equal 'Kayla',  Combiner.nth(['Mike', 'Kayla', 'Tucson'], index: 1)
  end

  def test_array
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

  def test_hash_merge
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

  def test_hash_merge_array
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

  def test_literal
    assert_equal 'x', Combiner.literal(['I', 'am', 'awesome'], value: 'x')
    assert_equal [], Combiner.literal(['I', 'am', 'awesome'], value: [])
  end

  def test_combiner_object
    c = Combiner.new(:name, with: :array, unique: true)
    assert_equal ['Mike', 'Tucson'], c.call(['Mike', 'Tucson', 'Tucson'])

    c = Combiner.new(:key, with: :smart_key)
    assert_equal 'ticket.close_create', c.call(['ticket.create', 'ticket.close'])
  end

  def test_combiner_block

    c = Combiner.new(:testing) do |values|
      values.reverse
    end

    assert_equal ['B', 'A'], c.call(['A',  'B'])

  end


end