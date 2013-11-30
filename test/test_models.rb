require 'ostruct'

# Give us 1.minute for convenience without brining in ActiveSupport
unless 1.respond_to?(:minute)
  class Numeric
    def minute
      self * 60
    end
    alias_method :minutes, :minute

    def hour
      minute * 60
    end
    alias_method :hours, :hour
  end
end


class TestModel < OpenStruct
  def inspect
    s = each_pair.map {|k,v| "#{k}=#{send(k).inspect}"}.join ' '
    "\#<#{self.class.name} #{s}>"
  end
end

class Ticket < TestModel
end

class Occupancy < TestModel
end

class User < TestModel
end

class Activity < TestModel
end
