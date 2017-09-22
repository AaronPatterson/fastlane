module Spaceship
  module Portal
    #
    # This class is a direct copy of the static methods exposed off of Spaceship::ProvisioningProfile
    #
    # NOTE: This class exists because we do not want the client instance shared across concurrent requests.
    #       This class exposes the static methods off of an instance so the client is not reused.
    #
    class ProvisioningProfiles
      def initialize(client)
        @client = client

        # Some checks are still done to ensure that a static instance has been set even though it is not used.
        # Set a dummy value to allow these checks to pass.
        Spaceship::ProvisioningProfile.set_client({})
      end

      # @return (String) The profile type used for web requests to the Dev Portal
      # @example
      #  "limited"
      #  "store"
      #  "adhoc"
      #  "inhouse"
      def type
        raise "You cannot create a ProvisioningProfile without a type. Use a subclass."
      end

      # Create a new object based on a hash.
      # This is used to create a new object based on the server response.
      def factory(attrs)
        # available values of `distributionMethod` at this point: ['adhoc', 'store', 'limited', 'direct']
        klass = case attrs['distributionMethod']
                  when 'limited'
                    Spaceship::ProvisioningProfile::Development
                  when 'store'
                    Spaceship::ProvisioningProfile::AppStore
                  when 'inhouse'
                    Spaceship::ProvisioningProfile::InHouse
                  when 'direct'
                    Spaceship::ProvisioningProfile::Direct # Mac-only
                  else
                    raise "Can't find class '#{attrs['distributionMethod']}'"
                end

        # Parse the dates
        # rubocop:disable Style/RescueModifier
        attrs['dateExpire'] = (Time.parse(attrs['dateExpire']) rescue attrs['dateExpire'])
        # rubocop:enable Style/RescueModifier

        # When a profile is created with a template name, the response
        # (provisioning profiles info) already contains the data about
        # template, which is used to instantiate the
        # ProvisioningProfileTemplate model.
        # Doing so saves an API call needed to fetch profile details.
        #
        # Verify if `attrs` contains the info needed to instantiate a template.
        # If not, the template will be lazily loaded.
        if attrs['profile'] && attrs['profile']['description']
          attrs['template'] = ProvisioningProfileTemplate.factory(attrs['template'])
        end

        klass.client = @client
        obj = klass.new(attrs)

        return obj
      end

      # @return (String) The human readable name of this profile type.
      # @example
      #  "AppStore"
      #  "AdHoc"
      #  "Development"
      #  "InHouse"
      def pretty_type
        name.split('::').last
      end

      # Create a new provisioning profile
      # @param name (String): The name of the provisioning profile on the Dev Portal
      # @param bundle_id (String): The app identifier, this parameter is required
      # @param certificate (Certificate): The certificate that should be used with this
      #   provisioning profile. You can also pass an array of certificates to this method. This will
      #   only work for development profiles
      # @param devices (Array) (optional): An array of Device objects that should be used in this profile.
      #  It is recommend to not pass devices as spaceship will automatically add all devices for AdHoc
      #  and Development profiles and add none for AppStore and Enterprise Profiles
      # @param mac (Bool) (optional): Pass true if you're making a Mac provisioning profile
      # @param sub_platform (String) Used to create tvOS profiles at the moment. Value should equal 'tvOS' or nil.
      # @param template_name (String) (optional): The name of the provisioning profile template.
      #  The value can be found by inspecting the Entitlements drop-down when creating/editing a
      #  provisioning profile in Developer Portal.
      # @return (ProvisioningProfile): The profile that was just created
      def create!(name: nil, bundle_id: nil, certificate: nil, devices: [], mac: false, sub_platform: nil, template_name: nil)
        raise "Missing required parameter 'bundle_id'" if bundle_id.to_s.empty?
        raise "Missing required parameter 'certificate'. e.g. use `Spaceship::Certificate::Production.all.first`" if certificate.to_s.empty?

        app = Spaceship::App.find(bundle_id, mac: mac)
        raise "Could not find app with bundle id '#{bundle_id}'" unless app

        raise "Invalid sub_platform #{sub_platform}, valid values are tvOS" if !sub_platform.nil? and sub_platform != 'tvOS'

        # Fill in sensible default values
        name ||= [bundle_id, pretty_type].join(' ')

        if self == AppStore || self == InHouse || self == Direct
          # Distribution Profiles MUST NOT have devices
          devices = []
        end

        certificate_parameter = certificate.collect(&:id) if certificate.kind_of? Array
        certificate_parameter ||= [certificate.id]

        # Fix https://github.com/KrauseFx/fastlane/issues/349
        certificate_parameter = certificate_parameter.first if certificate_parameter.count == 1

        if devices.nil? or devices.count == 0
          if self == Development or self == AdHoc
            # For Development and AdHoc we usually want all compatible devices by default
            if mac
              devices = Spaceship::Device.all_macs
            elsif sub_platform == 'tvOS'
              devices = Spaceship::Device.all_apple_tvs
            else
              devices = Spaceship::Device.all_ios_profile_devices
            end
          end
        end

        profile = @client.with_retry do
          @client.create_provisioning_profile!(name,
                                               self.type,
                                               app.app_id,
                                               certificate_parameter,
                                               devices.map(&:id),
                                               mac: mac,
                                               sub_platform: sub_platform,
                                               template_name: template_name)
        end

        self.new(profile)
      end

      # @return (Array) Returns all profiles registered for this account
      #  If you're calling this from a subclass (like AdHoc), this will
      #  only return the profiles that are of this type
      # @param mac (Bool) (optional): Pass true to get all Mac provisioning profiles
      # @param xcode (Bool) (optional): Pass true to include Xcode managed provisioning profiles
      def all(mac: false, xcode: false)
        if ENV['SPACESHIP_AVOID_XCODE_API']
          profiles = @client.provisioning_profiles(mac: mac)
        else
          profiles = @client.provisioning_profiles_via_xcode_api(mac: mac)
        end

        # transform raw data to class instances
        profiles.map! { |profile| self.factory(profile) }

        # filter out the profiles managed by xcode
        unless xcode
          profiles.delete_if(&:managed_by_xcode?)
        end

        return profiles
      end

      # @return (Array) Returns all profiles registered for this account
      #  If you're calling this from a subclass (like AdHoc), this will
      #  only return the profiles that are of this type
      def all_tvos
        profiles = all(mac: false)
        tv_os_profiles = []
        profiles.each do |tv_os_profile|
          if tv_os_profile.tvos?
            tv_os_profiles << tv_os_profile
          end
        end
        return tv_os_profiles
      end

      # @return (Array) Returns an array of provisioning
      #   profiles matching the bundle identifier
      #   Returns [] if no profiles were found
      #   This may also contain invalid or expired profiles
      def find_by_bundle_id(bundle_id: nil, mac: false, sub_platform: nil)
        raise "Missing required parameter 'bundle_id'" if bundle_id.to_s.empty?
        raise "Invalid sub_platform #{sub_platform}, valid values are tvOS" if !sub_platform.nil? and sub_platform != 'tvOS'
        find_tvos_profiles = sub_platform == 'tvOS'
        all(mac: mac).find_all do |profile|
          profile.app.bundle_id == bundle_id && profile.tvos? == find_tvos_profiles
        end
      end
    end
  end
end
