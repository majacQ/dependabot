# frozen_string_literal: true

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "dependabot/bundler/update_checker"
require "dependabot/bundler/update_checker/requirements_updater"
require "dependabot/bundler/file_updater/lockfile_updater"
require "dependabot/bundler/file_parser"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class UpdateChecker
      class ForceUpdater
        def initialize(dependency:, dependency_files:, repo_contents_path: nil,
                       credentials:, target_version:,
                       requirements_update_strategy:,
                       update_multiple_dependencies: true)
          @dependency                   = dependency
          @dependency_files             = dependency_files
          @repo_contents_path           = repo_contents_path
          @credentials                  = credentials
          @target_version               = target_version
          @requirements_update_strategy = requirements_update_strategy
          @update_multiple_dependencies = update_multiple_dependencies
        end

        def updated_dependencies
          @updated_dependencies ||= force_update
        end

        private

        attr_reader :dependency, :dependency_files, :repo_contents_path,
                    :credentials, :target_version, :requirements_update_strategy

        def update_multiple_dependencies?
          @update_multiple_dependencies
        end

        def force_update
          in_a_temporary_bundler_context do
            other_updates = []

            begin
              definition = build_definition(other_updates: other_updates)
              definition.resolve_remotely!
              specs = definition.resolve
              dependencies_from([dependency] + other_updates, specs)
            rescue ::Bundler::VersionConflict => e
              raise unless update_multiple_dependencies?

              # TODO: Not sure this won't unlock way too many things...
              new_dependencies_to_unlock =
                new_dependencies_to_unlock_from(
                  error: e,
                  already_unlocked: other_updates
                )

              raise if new_dependencies_to_unlock.none?

              other_updates += new_dependencies_to_unlock
              retry
            end
          end
        rescue SharedHelpers::ChildProcessFailed => e
          raise_unresolvable_error(e)
        end

        #########################
        # Bundler context setup #
        #########################

        def in_a_temporary_bundler_context
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_repo_directory(base_directory,
                                                      repo_contents_path) do
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              # Remove installed gems from the default Rubygems index
              ::Gem::Specification.all =
                ::Gem::Specification.send(:default_stubs, "*.gemspec")

              # Set flags and credentials
              set_bundler_flags_and_credentials

              yield
            end
          end
        end

        def new_dependencies_to_unlock_from(error:, already_unlocked:)
          potentials_deps =
            relevant_conflicts(error, already_unlocked).
            flat_map(&:requirement_trees).
            reject do |tree|
              # If the final requirement wasn't specific, it can't be binding
              next true if tree.last.requirement == Gem::Requirement.new(">= 0")

              # If the conflict wasn't for the dependency we're updating then
              # we don't have enough info to reject it
              next false unless tree.last.name == dependency.name

              # If the final requirement *was* for the dependency we're updating
              # then we can ignore the tree if it permits the target version
              tree.last.requirement.satisfied_by?(
                Gem::Version.new(target_version)
              )
            end.map(&:first)

          potentials_deps.
            reject { |dep| already_unlocked.map(&:name).include?(dep.name) }.
            reject { |dep| [dependency.name, "ruby\0"].include?(dep.name) }.
            uniq
        end

        def relevant_conflicts(error, dependencies_being_unlocked)
          names = [*dependencies_being_unlocked.map(&:name), dependency.name]

          # For a conflict to be relevant to the updates we're making it must be
          # 1) caused by a new requirement introduced by our unlocking, or
          # 2) caused by an old requirement that prohibits the update.
          # Hence, we look at the beginning and end of the requirement trees
          error.cause.conflicts.values.
            select do |conflict|
              conflict.requirement_trees.any? do |t|
                names.include?(t.last.name) || names.include?(t.first.name)
              end
            end
        end

        def raise_unresolvable_error(error)
          msg = error.error_class + " with message: " + error.error_message
          raise Dependabot::DependencyFileNotResolvable, msg
        end

        def build_definition(other_updates:)
          gems_to_unlock = other_updates.map(&:name) + [dependency.name]
          definition = ::Bundler::Definition.build(
            gemfile.name,
            lockfile&.name,
            gems: gems_to_unlock + subdependencies,
            lock_shared_dependencies: true
          )

          # Remove the Gemfile / gemspec requirements on the gems we're
          # unlocking (i.e., completely unlock them)
          gems_to_unlock.each do |gem_name|
            unlock_gem(definition: definition, gem_name: gem_name)
          end

          # Set the requirement for the gem we're forcing an update of
          new_req = Gem::Requirement.create("= #{target_version}")
          definition.dependencies.
            find { |d| d.name == dependency.name }.
            tap do |dep|
              dep.instance_variable_set(:@requirement, new_req)
              dep.source = nil if dep.source.is_a?(::Bundler::Source::Git)
            end

          definition
        end

        def subdependencies
          # If there's no lockfile we don't need to worry about
          # subdependencies
          return [] unless lockfile

          all_deps =  ::Bundler::LockfileParser.new(sanitized_lockfile_body).
                      specs.map(&:name).map(&:to_s)
          top_level = ::Bundler::Definition.
                      build(gemfile.name, lockfile.name, {}).
                      dependencies.map(&:name).map(&:to_s)

          all_deps - top_level
        end

        def unlock_gem(definition:, gem_name:)
          dep = definition.dependencies.find { |d| d.name == gem_name }
          version = definition.locked_gems.specs.
                    find { |d| d.name == gem_name }.version

          dep&.instance_variable_set(
            :@requirement,
            Gem::Requirement.create(">= #{version}")
          )
        end

        def original_dependencies
          @original_dependencies ||=
            FileParser.new(
              dependency_files: dependency_files,
              credentials: credentials,
              source: nil
            ).parse
        end

        def dependencies_from(updated_deps, specs)
          # You might think we'd want to remove dependencies whose version
          # hadn't changed from this array. We don't. We still need to unlock
          # them to get Bundler to resolve, because unlocking them is what
          # updates their subdependencies.
          #
          # This is kind of a bug in Bundler, and we should try to fix it,
          # but resolving it won't necessarily be easy.
          updated_deps.map do |dep|
            original_dep =
              original_dependencies.find { |d| d.name == dep.name }
            spec = specs.find { |d| d.name == dep.name }

            next if spec.version.to_s == original_dep.version

            build_dependency(original_dep, spec)
          end.compact
        end

        def build_dependency(original_dep, updated_spec)
          Dependency.new(
            name: updated_spec.name,
            version: updated_spec.version.to_s,
            requirements:
              RequirementsUpdater.new(
                requirements: original_dep.requirements,
                update_strategy: requirements_update_strategy,
                updated_source: source_for(original_dep),
                latest_version: updated_spec.version.to_s,
                latest_resolvable_version: updated_spec.version.to_s
              ).updated_requirements,
            previous_version: original_dep.version,
            previous_requirements: original_dep.requirements,
            package_manager: original_dep.package_manager
          )
        end

        def source_for(dependency)
          dependency.requirements.
            find { |r| r.fetch(:source) }&.
            fetch(:source)
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        def sanitized_lockfile_body
          re = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
          lockfile.content.gsub(re, "")
        end

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          File.write(lockfile.name, sanitized_lockfile_body) if lockfile
        end

        def set_bundler_flags_and_credentials
          # Set auth details
          relevant_credentials.each do |cred|
            token = cred["token"] ||
                    "#{cred['username']}:#{cred['password']}"

            ::Bundler.settings.set_command_option(
              cred.fetch("host"),
              token.gsub("@", "%40F").gsub("?", "%3F")
            )
          end

          # Only allow upgrades. Otherwise it's unlikely that this
          # resolution will be found by the FileUpdater
          ::Bundler.settings.set_command_option(
            "only_update_to_newer_versions",
            true
          )

          # Use HTTPS for GitHub if lockfile was generated by Bundler 2
          set_bundler_2_flags if using_bundler_2?
        end

        def set_bundler_2_flags
          ::Bundler.settings.set_command_option("forget_cli_options", "true")
          ::Bundler.settings.set_command_option("github.https", "true")
        end

        def relevant_credentials
          credentials.
            select { |cred| cred["password"] || cred["token"] }.
            select do |cred|
              next true if cred["type"] == "git_source"
              next true if cred["type"] == "rubygems_server"

              false
            end
        end

        def using_bundler_2?
          return unless lockfile

          lockfile.content.match?(/BUNDLED WITH\s+2/m)
        end
      end
    end
  end
end
