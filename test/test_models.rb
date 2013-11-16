require 'ostruct'

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
