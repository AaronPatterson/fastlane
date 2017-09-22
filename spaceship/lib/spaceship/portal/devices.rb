
module Spaceship
  module Portal
    #
    # This class is a direct copy of the static methods exposed off of Spaceship::Device
    #
    # NOTE: This class exists because we do not want the client instance shared across concurrent requests.
    #       This class exposes the static methods off of an instance so the client is not reused.
    #
    class Devices
      attr_accessor :client

      def initialize(client)
        @client = client

        # Some checks are still done to ensure that a static instance has been set even though it is not used.
        # Set a dummy value to allow these checks to pass.
       Spaceship::Device.set_client({})
      end

      # @param mac [Bool] Fetches Mac devices if true
      # @param include_disabled [Bool] Whether to include disable devices. false by default.
      # @return (Array) Returns all devices registered for this account
      def all(mac: false, include_disabled: false)
        @client.devices(mac: mac, include_disabled: include_disabled).map { |device| Spaceship::Device.factory(device) }
      end

      # @return (Array) Returns all Apple TVs registered for this account
      def all_apple_tvs
        @client.devices_by_class('tvOS').map { |device| Spaceship::Device.factory(device) }
      end

      # @return (Array) Returns all Watches registered for this account
      def all_watches
        @client.devices_by_class('watch').map { |device| Spaceship::Device.factory(device) }
      end

      # @return (Array) Returns all iPads registered for this account
      def all_ipads
        @client.devices_by_class('ipad').map { |device| Spaceship::Device.factory(device) }
      end

      # @return (Array) Returns all iPhones registered for this account
      def all_iphones
        @client.devices_by_class('iphone').map { |device| Spaceship::Device.factory(device) }
      end

      # @return (Array) Returns all iPods registered for this account
      def all_ipod_touches
        @client.devices_by_class('ipod').map { |device| Spaceship::Device.factory(device) }
      end

      # @return (Array) Returns all Macs registered for this account
      def all_macs
        all(mac: true)
      end

      # @return (Array) Returns all devices that can be used for iOS profiles (all devices except TVs)
      def all_ios_profile_devices
        all.reject { |device| device.device_type == "tvOS" }
      end

      # @return (Array) Returns all devices matching the provided profile_type
      def all_for_profile_type(profile_type)
        if profile_type.include? "tvOS"
          Spaceship::Device.all_apple_tvs
        elsif profile_type.include? "Mac"
          Spaceship::Device.all_macs
        else
          Spaceship::Device.all_ios_profile_devices
        end
      end

      # @param mac [Bool] Searches for Macs if true
      # @param include_disabled [Bool] Whether to include disable devices. false by default.
      # @return (Device) Find a device based on the ID of the device. *Attention*:
      #  This is *not* the UDID. nil if no device was found.
      def find(device_id, mac: false, include_disabled: false)
        all(mac: mac, include_disabled: include_disabled).find do |device|
          device.id == device_id
        end
      end

      # @param mac [Bool] Searches for Macs if true
      # @param include_disabled [Bool] Whether to include disable devices. false by default.
      # @return (Device) Find a device based on the UDID of the device. nil if no device was found.
      def find_by_udid(device_udid, mac: false, include_disabled: false)
        all(mac: mac, include_disabled: include_disabled).find do |device|
          device.udid.casecmp(device_udid) == 0
        end
      end

      # @param mac [Bool] Searches for Macs if true
      # @param include_disabled [Bool] Whether to include disable devices. false by default.
      # @return (Device) Find a device based on its name. nil if no device was found.
      def find_by_name(device_name, mac: false, include_disabled: false)
        all(mac: mac, include_disabled: include_disabled).find do |device|
          device.name == device_name
        end
      end

      # Register a new device to this account
      # @param name (String) (required): The name of the new device
      # @param udid (String) (required): The UDID of the new device
      # @param mac (Bool) (optional): Pass Mac if device is a Mac
      # @example
      #   Spaceship.device.create!(name: "Felix Krause's iPhone 6", udid: "4c24a7ee5caaa4847f49aaab2d87483053f53b65")
      # @return (Device): The newly created device
      def create!(name: nil, udid: nil, mac: false)
        # Check whether the user has passed in a UDID and a name
        unless udid && name
          raise "You cannot create a device without a device_id (UDID) and name"
        end

        # Find the device by UDID, raise an exception if it already exists
        existing = find_by_udid(udid, mac: mac)
        return existing if existing

        # It is valid to have the same name for multiple devices

        device = @client.create_device!(name, udid, mac: mac)

        # Update self with the new device
        Spaceship::Device.new(device)
      end
    end
  end
end
