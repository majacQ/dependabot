require "functions/lockfile_updater"
require "functions/file_parser"
require "functions/version_finder"

module Functions
  def self.parsed_gemfile(lockfile_name:, gemfile_name:, dir:)
    FileParser.new(dir: dir, lockfile_name: lockfile_name).
      parsed_gemfile(gemfile_name: gemfile_name)
  end

  def self.parsed_gemspec(lockfile_name:, gemspec_name:, dir:)
    FileParser.new(dir: dir, lockfile_name: lockfile_name).
      parsed_gemspec(gemspec_name: gemspec_name)
  end

  def self.vendor_cache_dir(dir:)
    # Set the path for path gemspec correctly
    Bundler.instance_variable_set(:@root, dir)
    Bundler.app_cache
  end

  def self.update_lockfile(gemfile_name:, lockfile_name:, using_bundler_2:,
                           dir:, credentials:, dependencies:)
    LockfileUpdater.new(
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      using_bundler_2: using_bundler_2,
      dir: dir,
      credentials: credentials,
      dependencies: dependencies,
    ).run
  end

  def self.dependency_source_type(gemfile_name:, dependency_name:, dir:,
                                  credentials:)
    VersionFinder.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name,
      dir: dir,
      credentials: credentials
    ).dependency_source_type
  end

  def self.private_registry_versions(gemfile_name:, dependency_name:, dir:,
                                     credentials:)
    VersionFinder.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name,
      dir: dir,
      credentials: credentials
    ).private_registry_versions
  end
end
