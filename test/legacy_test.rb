# We compare Coalesce's results against the old ActivityGrouper hack.  See
# legacy.rb for details.
#
# These are messy, as the results need to match exactly to pass.  This is NOT
# a good place to learn how to use the library.


require 'coalesce'

require 'minitest/unit'
require 'minitest/pride'
require 'minitest/autorun'

require 'csv'
require 'active_support/core_ext'

require_relative './test_models'
require_relative './legacy'

class LegacyTest < MiniTest::Unit::TestCase

  def legacy_grouper
    a = Legacy::ActivityGrouper.new

    # Bob created #123, A, B, and C were notified -> ticket.notify_create
    a.rule same: [:trackable, :owner],
           combine: [:key, :recipient],
           uniq: [:recipient],
           lock: true,
           time_delta: 5.minutes do |batch, r|
      result = batch.prototype.key == 'ticket.create' &&
        batch.objects[1..-1].all? {|a| a.key == 'ticket.notify'} &&
          r.key == 'ticket.notify'
      result
    end

    # Combines accept + comment, suspended, so the next rule can pick it up
    # a.rule same:    [:trackable, :owner],
    #        combine: [:trackable, :key, :parameters],
    #        uniq:    [:trackable],
    #        merge:   [:parameters],
    #        time_delta: 1.hour,
    #        suspended: true do |batch, r|
    #   (batch.objects.map(&:key) == ['ticket.accept'] && r.key == 'comment.create')
    # end

    # Bob closed #123 with comment.  Grabs either comment + close or
    # accept + comment + close
    a.rule same:    [:trackable, :owner],
           combine: [:trackable, :key, :parameters],
           uniq:    [:trackable],
           merge:   [:parameters],
           time_delta: 1.hour,
           lock: true do |batch, r|
      (batch.objects.map(&:key) == ['comment.create'] && r.key == 'ticket.close') ||
        (batch.objects.map(&:key) == ['ticket.accept', 'comment.create'] && r.key == 'ticket.close')
    end

    a.rule key: 'ticket.accept',
           same: [:recipient, :owner],
           combine: [:trackable],
           uniq: [:trackable],
           lock: true,
           time_delta: 1.hour

    a.rule key: 'ticket.close',
           same: [:recipient, :owner],
           combine: [:trackable],
           lock: true,
           time_delta: 1.hour

    a.rule key: 'ticket.update',
           same: [:recipient, :trackable],
           combine: [:trackable],
           uniq: [:trackable],
           lock: true,
           time_delta: 1.hour

    a.rule key: 'ticket.notify',
           same: [:trackable, :owner],
           combine: [:recipient],
           uniq: [:recipient],
           lock: true,
           time_delta: 1.hour

    a.rule key: 'ticket.important',
           same:    [:trackable, :owner],
           combine: [:trackable, :owner],
           uniq:    [:trackable, :owner],
           lock: true,
           time_delta: 1.hour

    a.rule key: 'ticket.priority',
           same:    [:trackable, :owner],
           combine: [:trackable, :owner],
           uniq:    [:trackable, :owner],
           lock: true,
           time_delta: 1.hour

    return a
  end

  def coalesce_grouper
    Coalesce::Grouper.new do
      rule :merge_create_plus_notifications do
        same       :trackable, :owner
        time_delta 5.minutes, from: :first

        # The original has an explicit predicate that requires the prototype to
        # be 'ticket.create' and the rest collected thus far to be
        # 'ticket.notify'.  This isn't really required, but provided for
        # consistency.

        predicate! do |batch, candidate|
          batch.prototype.key == 'ticket.create' &&
            batch.objects[1..-1].all? {|a| a.key == 'ticket.notify' } &&
            candidate.key == 'ticket.notify'
        end

        lock
        combine :key, with: :smart_key
        combine :recipient, unique: true
      end

      # rule :accept_plus_comment do
      #   same       :trackable, :owner
      #   time_delta 1.hour, from: :first

      #   predicate! do |batch, candidate|
      #     batch.prototype.key == 'ticket.accept' && candidate.key == 'comment.create'
      #   end

      #   suspend
      #   combine :key, with: :smart_key
      #   combine :trackable, unique: true
      #   combine :parameters, with: :hash_merge_array
      # end

      rule :close_with_comment do
        same       :trackable, :owner
        time_delta 1.hour, from: :first

        predicate! do |batch, candidate|
          (batch.prototype.key == 'comment.create' && candidate.key == 'ticket.close') ||
            (batch.objects.map(&:key) == ['ticket.accept', 'comment.create'] &&
              candidate.key == 'ticket.close')
        end

        combine :key, with: :smart_key
        combine :trackable, unique: true, singular: true
        combine :parameters, with: :hash_merge_array,
                             combiner: :array,
                             combiner_options: {singular: true}
      end

      rule :combine_accepts do
        key        'ticket.accept'
        same       :recipient, :owner
        time_delta 1.hour, from: :first

        lock
        combine :trackable, unique: true, singular: true
      end


      rule :combine_closes do
        key        'ticket.close'
        same       :recipient, :owner
        time_delta 1.hour, from: :first

        lock
        combine :trackable, singular: true
      end

      rule :combine_updates do
        key        'ticket.update'
        same       :recipient, :trackable
        time_delta 1.hour, from: :first

        lock
        combine :trackable, unique: true, singular: true
      end

      rule :combine_notifies do
        key 'ticket.notify'
        same :trackable, :owner
        time_delta 1.hour, from: :first

        lock
        combine :recipient, unique: true, singular: true
      end

      rule :combine_importants do
        key        'ticket.important'
        same       :trackable, :owner
        time_delta 1.hour, from: :first

        lock
        combine :trackable, unique: true, singular: true
        combine :owner,     unique: true, singular: true
      end

      rule :combine_priority_changes do
        key       'ticket.priority'
        same      :trackable, :owner
        time_delta 1.hour, from: :first

        lock
        combine :trackable, unique: true, singular: true
        combine :owner,     unique: true, singular: true
      end
    end
  end


  def test_initialize
    # Let this generate an error if they can't be instantiated for
    # whatever reason.
    a = activities
    from_legacy = legacy_grouper.each(a)
    from_coalesce = coalesce_grouper.each(a)

    loop do
      l = from_legacy.next
      r = from_coalesce.next

      %i(batched? key id owner parameters trackable created_at).each do |k|
        assert_equal l.send(k), r.send(k)
      end
    end
  end

  def activities
    return enum_for(__method__) unless block_given?
    CSV.foreach(File.dirname(__FILE__) + "/legacy.csv") do |row|
      id, trackable_id, trackable_type, owner_id, owner_type,
      key, parameters, recipient_id, recipient_type,
      created_at, updated_at, read_at = row

      yield Activity.new \
        id: id.to_i,
        trackable: trackable_type == 'Ticket' ?
                     Ticket.new(id: trackable_id.to_i) :
                     Occupancy.new(id: trackable_id.to_i),
        owner: owner_id ? User.new(id: owner_id.to_i) : nil,
        key: key,
        parameters: parameters ? eval(parameters) : {},
        recipient: recipient_id ? User.new(id: recipient_id.to_i) : nil,
        created_at: DateTime.parse(created_at)
    end
  end
end