require "functions/lockfile_updater"
require "functions/file_parser"
require "functions/dependency_source"

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
    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name,
      dir: dir,
      credentials: credentials
    ).type
  end

  def self.depencency_source_latest_git_version(gemfile_name:, dependency_name:,
                                                dir:, credentials:,
                                                dependency_source_url:,
                                                dependency_source_branch:)
    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name,
      dir: dir,
      credentials: credentials
    ).latest_git_version(
      dependency_source_url: dependency_source_url,
      dependency_source_branch: dependency_source_branch
    )
  end

  def self.private_registry_versions(gemfile_name:, dependency_name:, dir:,
                                     credentials:)
    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name,
      dir: dir,
      credentials: credentials
    ).private_registry_versions
  end
end
