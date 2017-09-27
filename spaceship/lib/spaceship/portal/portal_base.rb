module Spaceship
  class PortalBase < Spaceship::Base
    class << self
      def client
        (
          #
          # NOTE: We never want the static client to be used.  Setting up to always return dummy
          #       value so there is not chance of it accidentally being used.
          #
          # @client or
          # Spaceship::Portal.client or
          # raise "Please login using `Spaceship::Portal.login('user', 'password')`"
          {}
        )
      end
    end
  end
end
