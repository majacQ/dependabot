# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require "dependabot/bundler/file_parser/file_preparer"
      require "dependabot/bundler/file_parser/gemfile_declaration_finder"

      def parse
        dependency_set = DependencySet.new
        dependency_set += gemfile_dependencies
        dependency_set += gemspec_dependencies
        dependency_set += lockfile_dependencies
        dependency_set.dependencies
      end

      private

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

      def gemfile_dependencies
        dependencies = DependencySet.new

        return dependencies unless gemfile

        [gemfile, *evaled_gemfiles].each do |file|
          parsed_gemfile.each do |dep|
            gemfile_declaration_finder =
              GemfileDeclarationFinder.new(dependency: dep, gemfile: file)
            next unless gemfile_declaration_finder.gemfile_includes_dependency?

            dependencies <<
              Dependency.new(
                name: dep.name,
                version: dependency_version(dep.name)&.to_s,
                requirements: [{
                  requirement: gemfile_declaration_finder.enhanced_req_string,
                  groups: dep.groups,
                  source: source_for(dep),
                  file: file.name
                }],
                package_manager: "bundler"
              )
          end
        end

        dependencies
      end

      def gemspec_dependencies
        dependencies = DependencySet.new

        gemspecs.each do |gemspec|
          parsed_gemspec(gemspec).dependencies.each do |dependency|
            dependencies <<
              Dependency.new(
                name: dependency.name,
                version: dependency_version(dependency.name)&.to_s,
                requirements: [{
                  requirement: dependency.requirement.to_s,
                  groups: dependency.runtime? ? ["runtime"] : ["development"],
                  source: source_for(dependency),
                  file: gemspec.name
                }],
                package_manager: "bundler"
              )
          end
        end

        dependencies
      end

      def lockfile_dependencies
        dependencies = DependencySet.new

        return dependencies unless lockfile

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        parsed_lockfile.specs.each do |dependency|
          next if dependency.source.is_a?(::Bundler::Source::Path)

          dependencies <<
            Dependency.new(
              name: dependency.name,
              version: dependency_version(dependency.name)&.to_s,
              requirements: [],
              package_manager: "bundler",
              subdependency_metadata: [{
                production: production_dep_names.include?(dependency.name)
              }]
            )
        end

        dependencies
      end

      def parsed_gemfile
        @parsed_gemfile ||=
          SharedHelpers.in_a_temporary_repo_directory(base_directory,
                                                      repo_contents_path) do
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))

              ::Bundler::Definition.build(gemfile.name, nil, {}).
                dependencies.
                select(&:current_platform?).
                # We can't dump gemspec sources, and we wouldn't bump them
                # anyway, so we filter them out.
                reject { |dep| dep.source.is_a?(::Bundler::Source::Gemspec) }
            end
          end
      rescue SharedHelpers::ChildProcessFailed, ArgumentError => e
        handle_marshall_error(e) if e.is_a?(ArgumentError)

        msg = e.error_class + " with message: " +
              e.error_message.force_encoding("UTF-8").encode
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      def handle_marshall_error(err)
        raise err unless err.message == "marshal data too short"

        msg = "Error evaluating your dependency files: #{err.message}"
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      def parsed_gemspec(file)
        @parsed_gemspecs ||= {}
        @parsed_gemspecs[file.name] ||=
          SharedHelpers.in_a_temporary_repo_directory(base_directory,
                                                      repo_contents_path) do
            [file, *imported_ruby_files].each do |f|
              path = f.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, f.content)
            end

            SharedHelpers.in_a_forked_process do
              ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
              ::Bundler.load_gemspec_uncached(file.name)
            end
          end
      rescue SharedHelpers::ChildProcessFailed => e
        msg = e.error_class + " with message: " + e.error_message
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      def base_directory
        dependency_files.first.directory
      end

      def prepared_dependency_files
        @prepared_dependency_files ||=
          FilePreparer.new(dependency_files: dependency_files).
          prepared_dependency_files
      end

      def write_temporary_dependency_files
        prepared_dependency_files.each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, file.content)
        end
      end

      def check_required_files
        file_names = dependency_files.map(&:name)

        return if file_names.any? do |name|
          name.end_with?(".gemspec") && !name.include?("/")
        end

        return if gemfile

        raise "A gemspec or Gemfile must be provided!"
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

      def dependency_version(dependency_name)
        return unless lockfile

        spec = parsed_lockfile.specs.find { |s| s.name == dependency_name }

        # Not all files in the Gemfile will appear in the Gemfile.lock. For
        # instance, if a gem specifies `platform: [:windows]`, and the
        # Gemfile.lock is generated on a Linux machine, the gem will be not
        # appear in the lockfile.
        return unless spec

        # If the source is Git we're better off knowing the SHA-1 than the
        # version.
        if spec.source.instance_of?(::Bundler::Source::Git)
          return spec.source.revision
        end

        spec.version
      end

      def source_from_lockfile(dependency_name)
        parsed_lockfile.specs.find { |s| s.name == dependency_name }&.source
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile") ||
                     get_original_file("gems.rb")
      end

      def evaled_gemfiles
        dependency_files.
          reject { |f| f.name.end_with?(".gemspec") }.
          reject { |f| f.name.end_with?(".specification") }.
          reject { |f| f.name.end_with?(".lock") }.
          reject { |f| f.name.end_with?(".ruby-version") }.
          reject { |f| f.name == "Gemfile" }.
          reject { |f| f.name == "gems.rb" }.
          reject { |f| f.name == "gems.locked" }
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock") ||
                      get_original_file("gems.locked")
      end

      def parsed_lockfile
        @parsed_lockfile ||=
          ::Bundler::LockfileParser.new(sanitized_lockfile_content)
      end

      def production_dep_names
        @production_dep_names ||=
          (gemfile_dependencies + gemspec_dependencies).dependencies.
          select { |dep| production?(dep) }.
          flat_map { |dep| expanded_dependency_names(dep) }.
          uniq
      end

      def expanded_dependency_names(dep)
        spec = parsed_lockfile.specs.find { |s| s.name == dep.name }
        return [dep.name] unless spec

        [
          dep.name,
          *spec.dependencies.flat_map { |d| expanded_dependency_names(d) }
        ]
      end

      def production?(dependency)
        groups = dependency.requirements.
                 flat_map { |r| r.fetch(:groups) }.
                 map(&:to_s)

        return true if groups.empty?
        return true if groups.include?("runtime")
        return true if groups.include?("default")

        groups.any? { |g| g.include?("prod") }
      end

      def sanitized_lockfile_content
        regex = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
        lockfile.content.gsub(regex, "")
      end

      def gemspecs
        # Path gemspecs are excluded (they're supporting files)
        @gemspecs ||= prepared_dependency_files.
                      select { |file| file.name.end_with?(".gemspec") }.
                      reject(&:support_file?)
      end

      def imported_ruby_files
        dependency_files.
          select { |f| f.name.end_with?(".rb") }.
          reject { |f| f.name == "gems.rb" }
      end
    end
  end
end

Dependabot::FileParsers.register("bundler", Dependabot::Bundler::FileParser)
