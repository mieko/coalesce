require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'coalesce/rule'
require 'coalesce/batch'

require_relative 'test_models'

class RuleTest < MiniTest::Unit::TestCase
  include Coalesce

  def a!(*args, **kw)
    Activity.new(*args, **kw)
  end

  def epoch
    @epoch ||= Time.now
  end

  def test_rule_dsl
    rule = Rule.new 'ticket.close_accept' do
      attr_in :key, 'ticket.accept', 'ticket.close'
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

  def test_rule
    activities = [
      a!(key: 'ticket.accept',  ticket: 1, owner: 'Mike', created_at: epoch),
      a!(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch + 1.minutes),
      a!(key: 'ticket.comment', ticket: 1, owner: 'Mike', created_at: epoch + 2.minutes),
      a!(key: 'ticket.close',   ticket: 1, owner: 'Mike', created_at: epoch + 3.minutes),
      a!(key: 'ticket.close',   ticket: 1, owner: 'Bob',  created_at: epoch + 4.minutes)
    ]

    rule = Rule.new('ticket.accept_close') do
      attr_in :key, 'ticket.accept', 'ticket.close'
      same :ticket, :owner
    end

    batch = Batch.new(activities.first)

    assert_equal true,  rule.matches?(batch, activities[0])
    assert_equal true,  rule.matches?(batch, activities[1])
    assert_equal false, rule.matches?(batch, activities[2])
    assert_equal true,  rule.matches?(batch, activities[3])
    assert_equal false, rule.matches?(batch, activities[4])
  end

end