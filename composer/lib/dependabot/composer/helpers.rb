# frozen_string_literal: true

require "dependabot/composer/version"

module Dependabot
  module Composer
    module Helpers
      # From composers json-schema: https://getcomposer.org/schema.json
      COMPOSER_V2_NAME_REGEX = %r{^[a-z0-9]([_.-]?[a-z0-9]+)*/[a-z0-9](([_.]?|-{0,2})[a-z0-9]+)*$}.freeze

      def self.composer_version(composer_json, parsed_lockfile = nil)
        return "v1" if composer_json["name"] && composer_json["name"] !~ COMPOSER_V2_NAME_REGEX
        return "v1" if invalid_v2_requirement?(composer_json)
        return "v2" unless parsed_lockfile && parsed_lockfile["plugin-api-version"]

        version = Composer::Version.new(parsed_lockfile["plugin-api-version"])
        version.canonical_segments.first == 1 ? "v1" : "v2"
      end

      def self.invalid_v2_requirement?(composer_json)
        return false unless composer_json.key?("require")

        composer_json["require"].keys.any? do |key|
          key != "php" && key !~ COMPOSER_V2_NAME_REGEX
        end
      end
      private_class_method :invalid_v2_requirement?
    end
  end
end
