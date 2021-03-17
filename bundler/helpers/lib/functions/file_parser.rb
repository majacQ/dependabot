module Functions
  class FileParser
    # TODO: Remove the need to sanitize BUNDLED WITH (requires multiple
    # installed bundler versions)
    #
    # Note: Copied from FileUpdater::LockfileUpdater
    LOCKFILE_ENDING =  /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m.freeze

    def initialize(dir:, lockfile_name:)
      @dir = dir
      @lockfile_name = lockfile_name
    end

    attr_reader :dir, :lockfile_name

    def parsed_gemfile(gemfile_name:)
      Bundler.instance_variable_set(:@root, dir)

      Bundler::Definition.build(gemfile_name, nil, {}).
        dependencies.select(&:current_platform?).
        reject { |dep| dep.source.is_a?(Bundler::Source::Gemspec) }.
        map(&method(:serialize_bundler_dependency))
    end

    def parsed_gemspec(gemspec_name:)
      Bundler.instance_variable_set(:@root, dir)
      Bundler.load_gemspec_uncached(gemspec_name).
        dependencies.
        map(&method(:serialize_bundler_dependency))
    end

    private

    def lockfile
      Dir.chdir(dir) do
        return unless lockfile_name && File.exist?(lockfile_name)

        @lockfile ||= File.read(lockfile_name)
      end
    end

    def sanitized_lockfile
      lockfile.gsub(LOCKFILE_ENDING, "")
    end

    def parsed_lockfile
      return unless lockfile

      @parsed_lockfile ||= ::Bundler::LockfileParser.new(sanitized_lockfile)
    end

    def source_from_lockfile(dependency_name)
      parsed_lockfile&.specs.find { |s| s.name == dependency_name }&.source
    end

    def source_for(dependency)
      source = dependency.source
      if lockfile && default_rubygems?(source)
        # If there's a lockfile and the Gemfile doesn't have anything
        # interesting to say about the source, check that.
        source = source_from_lockfile(dependency.name)
      end
      raise "Bad source: #{source}" unless sources.include?(source.class)

      return nil if default_rubygems?(source)

      details = { type: source.class.name.split("::").last.downcase }
      if source.is_a?(::Bundler::Source::Git)
        details.merge!(git_source_details(source))
      end
      if source.is_a?(::Bundler::Source::Rubygems)
        details[:url] = source.remotes.first.to_s
      end
      details
    end

    def git_source_details(source)
      {
        url: source.uri,
        branch: source.branch || "master",
        ref: source.ref
      }
    end

    def default_rubygems?(source)
      return true if source.nil?
      return false unless source.is_a?(::Bundler::Source::Rubygems)

      source.remotes.any? { |r| r.to_s.include?("rubygems.org") }
    end

    def serialize_bundler_dependency(dependency)
      {
        name: dependency.name,
        requirement: dependency.requirement,
        groups: dependency.groups,
        source: source_for(dependency),
        type: dependency.type
      }
    end

    # Can't be a constant because some of these don't exist in bundler
    # 1.15, which Heroku uses, which causes an exception on boot.
    def sources
      [
        NilClass,
        ::Bundler::Source::Rubygems,
        ::Bundler::Source::Git,
        ::Bundler::Source::Path,
        ::Bundler::Source::Gemspec,
        ::Bundler::Source::Metadata
      ]
    end
  end
end
