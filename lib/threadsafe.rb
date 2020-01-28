require 'thread'

module NMEAPlusGoogleEarth

  # This class wraps any given object to provide mutex protection
  class ThreadSafeWrapper

    # @param obj - any object
    def initialize(obj)
      @obj = obj
      @mutex = Mutex.new
    end

    # @param block - block that takes the input object as a parameter, with thread safety taken care of
    def safely(&block)
      @mutex.synchronize do
        block.call(@obj)
      end
    end
  end
end
