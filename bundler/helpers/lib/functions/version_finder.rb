module Functions
  class VersionFinder
    attr_reader :gemfile_name, :dependency_name, :dir, :credentials

    def initialize(gemfile_name:, dependency_name:, dir:, credentials:)
      @gemfile_name = gemfile_name
      @dependency_name = dependency_name
      @dir = dir
      @credentials = credentials
    end

    def dependency_source_type
      return "git" if dependency_source.is_a?(::Bundler::Source::Git)

      if dependency_source.is_a?(::Bundler::Source::Rubygems)
        remote = dependency_source.remotes.first

        if remote.nil? || remote.to_s == "https://rubygems.org/"
          "rubygems"
        else
          "private_registry"
        end
      else
        "unknown"
      end
    end

    def dependency_source
      setup_bundler

      specified_source || default_source
    end

    def private_registry_versions
      setup_bundler

      dependency_source.fetchers.flat_map do |fetcher|
        fetcher.
          specs_with_retry([dependency_name], dependency_source).
          search_all(dependency_name)
      end.map(&:version)
    end

    private

    def setup_bundler
      ::Bundler.instance_variable_set(:@root, dir)

      # TODO: DRY out this setup with Functions::LockfileUpdater
      credentials.each do |cred|
        token = cred["token"] ||
                "#{cred['username']}:#{cred['password']}"

        ::Bundler.settings.set_command_option(
          cred.fetch("host"),
          token.gsub("@", "%40F").gsub("?", "%3F")
        )
      end
    end

    def serialize_bundler_source
      {
        type: source.class.to_s
      }
    end

    def specified_source
      return @specified_source if defined? @specified_source

      @specified_source = definition.dependencies.
        find { |dep| dep.name == dependency_name }&.source
    end

    def default_source
      definition.send(:sources).default_source
    end

    def definition
      @definition ||= ::Bundler::Definition.build(gemfile_name, nil, {})
    end

    def serialize_bundler_source(source)
      {
        type: source.class.to_s
      }
    end
  end
end
