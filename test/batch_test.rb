require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'coalesce/batch'

require_relative './test_models'

# Some ORMs override dup to do weird things to represent
# a new record.  This object clears timestamps and ID to
# make sure dup or clone isn't called on a standin.
class ORMLikeObject < Activity
  def dup
    super.tap do |r|
      r.created_at = nil
      r.id = nil
    end
  end

  def clone
    dup
  end
end

class BatchTest < MiniTest::Unit::TestCase
  include Coalesce

  def test_standin_doesnt_dup
    t = Time.now

    obj1 = ORMLikeObject.new(id: 5, created_at: t, name: 'Bob')
    assert_equal t, obj1.created_at

    obj2 = obj1.dup
    refute_equal obj1.object_id, obj2.object_id

    assert_nil obj2.created_at

    batch = Batch.new(obj1)
    result = batch.to_standin

    assert_equal obj1.id, result.id
    assert_equal obj1.created_at, result.created_at
  end

end