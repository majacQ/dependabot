# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::NpmAndYarn::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [package_json, lockfile] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("package_files", package_json_fixture_name)
    )
  end
  let(:package_json_fixture_name) { "package.json" }
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source,
      credentials: credentials
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    describe "top level dependencies" do
      subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

      context "with no lockfile" do
        let(:package_json_fixture_name) { "exact_version_requirements.json" }
        let(:files) { [package_json] }
        its(:length) { is_expected.to eq(3) }
      end

      context "with a package-lock.json" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: lockfile_body
          )
        end
        let(:lockfile_body) do
          fixture("npm_lockfiles", npm_lock_fixture_name)
        end
        let(:npm_lock_fixture_name) { "package-lock.json" }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a blank requirement" do
          let(:package_json_fixture_name) { "blank_requirement.json" }
          let(:npm_lock_fixture_name) { "blank_requirement.json" }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.2.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "*",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with an ignored hash requirement" do
          let(:package_json_fixture_name) { "hash_requirement.json" }
          let(:npm_lock_fixture_name) { "package-lock.json" }

          its(:length) { is_expected.to eq(2) }
        end

        context "that contains an empty version string for a sub-dep" do
          let(:npm_lock_fixture_name) { "empty_version.json" }

          its(:length) { is_expected.to eq(2) }
        end

        context "that contains a version requirement string" do
          let(:npm_lock_fixture_name) { "invalid_version_requirement.json" }
          subject { dependencies.find { |d| d.name == "etag" } }
          it { is_expected.to eq(nil) }
        end

        context "that has URL versions (i.e., is from a bad version of npm)" do
          let(:package_json_fixture_name) { "url_versions.json" }
          let(:npm_lock_fixture_name) { "url_versions.json" }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("hashids") }
            its(:version) { is_expected.to eq("1.1.4") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.1.4",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with only dev dependencies" do
          let(:package_json_fixture_name) { "only_dev_dependencies.json" }
          let(:npm_lock_fixture_name) { "only_dev_dependencies.json" }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "when the dependency is specified as both dev and runtime" do
          let(:package_json_fixture_name) { "duplicate.json" }
          let(:files) { [package_json] }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to be_nil }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "0.1.x",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }, {
                  requirement: "^0.1.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a private-source dependency" do
          let(:package_json_fixture_name) { "private_source.json" }
          let(:npm_lock_fixture_name) { "private_source.json" }

          its(:length) { is_expected.to eq(7) }

          describe "the first private dependency" do
            subject { top_level_dependencies[1] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("chalk") }
            its(:version) { is_expected.to eq("2.3.0") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: {
                    type: "private_registry",
                    url: "http://registry.npm.taobao.org"
                  }
                }]
              )
            end
          end

          describe "the gemfury dependency" do
            subject { top_level_dependencies[2] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/etag") }
            its(:version) { is_expected.to eq("1.8.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://npm.fury.io/dependabot"
                  }
                }]
              )
            end
          end

          describe "the GPR dependency" do
            subject { top_level_dependencies[5] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core-3") }
            its(:version) { is_expected.to eq("2.0.14") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://npm.pkg.github.com"
                  }
                }]
              )
            end
          end

          describe "the scoped gitlab dependency" do
            subject { top_level_dependencies[6] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core-4") }
            its(:version) { is_expected.to eq("2.0.14") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://gitlab.mydomain.com/api/v4/"\
                         "packages/npm"
                  }
                }]
              )
            end
          end

          describe "the scoped artifactory dependency" do
            subject { top_level_dependencies[3] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core") }
            its(:version) { is_expected.to eq("2.0.14") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://artifactory01.mydomain.com/artifactory/api/"\
                         "npm/my-repo"
                  }
                }]
              )
            end
          end

          describe "the unscoped artifactory dependency" do
            subject { top_level_dependencies[0] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://artifactory01.mydomain.com/artifactory/api/"\
                         "npm/my-repo"
                  }
                }]
              )
            end

            context "with credentials" do
              let(:credentials) do
                [{
                  "type" => "npm_registry",
                  "registry" =>
                    "artifactory01.mydomain.com/artifactory/api/npm/my-repo",
                  "token" => "secret_token"
                }]
              end

              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^0.0.1",
                    file: "package.json",
                    groups: ["dependencies"],
                    source: {
                      type: "private_registry",
                      url: "https://artifactory01.mydomain.com/artifactory/"\
                           "api/npm/my-repo"
                    }
                  }]
                )
              end

              context "excluding the auth token" do
                let(:credentials) do
                  [{
                    "type" => "npm_registry",
                    "registry" =>
                      "artifactory01.mydomain.com/artifactory/api/npm/my-repo"
                  }]
                end

                its(:requirements) do
                  is_expected.to eq(
                    [{
                      requirement: "^0.0.1",
                      file: "package.json",
                      groups: ["dependencies"],
                      source: {
                        type: "private_registry",
                        url: "https://artifactory01.mydomain.com/artifactory/"\
                             "api/npm/my-repo"
                      }
                    }]
                  )
                end
              end
            end
          end

          describe "the bintray dependency" do
            subject { top_level_dependencies[4] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/pack-core-2") }
            its(:version) { is_expected.to eq("2.0.14") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.1",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://api.bintray.com/npm/dependabot/npm-private"
                  }
                }]
              )
            end
          end
        end

        context "with an optional dependency" do
          let(:package_json_fixture_name) { "optional_dependencies.json" }
          let(:npm_lock_fixture_name) { "optional_dependencies.json" }

          its(:length) { is_expected.to eq(2) }

          describe "the last dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["optionalDependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a path-based dependency" do
          let(:files) { [package_json, lockfile, path_dep] }
          let(:package_json_fixture_name) { "path_dependency.json" }
          let(:npm_lock_fixture_name) { "path_dependency.json" }
          let(:path_dep) do
            Dependabot::DependencyFile.new(
              name: "deps/etag/package.json",
              content: fixture("package_files", "etag.json"),
              support_file: true
            )
          end

          it "doesn't include the path-based dependency" do
            expect(top_level_dependencies.length).to eq(3)
            expect(top_level_dependencies.map(&:name)).to_not include("etag")
          end
        end

        context "with a git-url dependency" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "git_dependency.json" }
          let(:npm_lock_fixture_name) { "git_dependency.json" }

          its(:length) { is_expected.to eq(4) }

          describe "the git dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }
            its(:version) do
              is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
            end
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: nil,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number.git",
                    branch: nil,
                    ref: "master"
                  }
                }]
              )
            end

            context "when the lockfile has a branch for the version" do
              let(:npm_lock_fixture_name) do
                "git_dependency_branch_version.json"
              end

              it "is excluded" do
                expect(top_level_dependencies.map(&:name)).
                  to_not include("is-number")
              end
            end
          end
        end

        context "with a github dependency" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "github_dependency.json" }
          let(:npm_lock_fixture_name) { "github_dependency.json" }

          its(:length) { is_expected.to eq(1) }

          describe "the github dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }
            its(:version) do
              is_expected.to eq("d5ac0584ee9ae7bd9288220a39780f155b9ad4c8")
            end
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: nil,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number",
                    branch: nil,
                    ref: "2.0.0"
                  }
                }]
              )
            end
          end

          context "that specifies a semver requirement" do
            let(:files) { [package_json, lockfile] }
            let(:package_json_fixture_name) { "github_dependency_semver.json" }
            let(:npm_lock_fixture_name) { "github_dependency_semver.json" }

            before do
              git_url = "https://github.com/jonschlinkert/is-number.git"
              git_header = {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
              pack_url = git_url + "/info/refs?service=git-upload-pack"
              stub_request(:get, pack_url).
                with(basic_auth: %w(x-access-token token)).
                to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", git_pack_fixture_name),
                  headers: git_header
                )
            end
            let(:git_pack_fixture_name) { "is-number" }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) { is_expected.to eq("2.0.2") }
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^2.0.0",
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end

              context "when a tag can't be found" do
                let(:git_pack_fixture_name) { "manifesto" }
                its(:version) do
                  is_expected.to eq("63d5b26c793194bf7f341a7203e0e5568c753539")
                end
              end

              context "when the git repo can't be found" do
                before do
                  git_url = "https://github.com/jonschlinkert/is-number.git"
                  pack_url = git_url + "/info/refs?service=git-upload-pack"
                  stub_request(:get, pack_url).
                    with(basic_auth: %w(x-access-token token)).
                    to_return(status: 404)
                end

                its(:version) do
                  is_expected.to eq("63d5b26c793194bf7f341a7203e0e5568c753539")
                end
              end
            end
          end

          context "that doesn't specify a reference" do
            let(:files) { [package_json, lockfile] }
            let(:package_json_fixture_name) { "github_dependency_no_ref.json" }
            let(:npm_lock_fixture_name) { "github_dependency_no_ref.json" }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) do
                is_expected.to eq("d5ac0584ee9ae7bd9288220a39780f155b9ad4c8")
              end
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end
          end

          context "that is specified with its shortname" do
            let(:files) { [package_json, lockfile] }
            let(:package_json_fixture_name) { "github_shortname.json" }
            let(:npm_lock_fixture_name) { "github_shortname.json" }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) do
                is_expected.to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
              end
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end
          end
        end

        context "with only a package.json" do
          let(:files) { [package_json] }

          its(:length) { is_expected.to eq(2) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to be_nil }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end

          context "with a git dependency" do
            let(:package_json_fixture_name) { "git_dependency.json" }
            its(:length) { is_expected.to eq(4) }

            describe "the git dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) { is_expected.to be_nil }
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number.git",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end

            context "when the dependency also has a non-git source" do
              let(:package_json_fixture_name) { "multiple_sources.json" }

              it "excludes the dependency" do
                expect(dependencies.map(&:name)).to eq(["fetch-factory"])
              end
            end
          end

          context "that does flat resolution" do
            let(:package_json_fixture_name) { "flat.json" }
            its(:length) { is_expected.to eq(0) }
          end
        end
      end

      context "with an npm-shrinkwrap.json" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "npm-shrinkwrap.json",
            content: lockfile_body
          )
        end
        let(:lockfile_body) do
          fixture("shrinkwraps", shrinkwrap_fixture_name)
        end
        let(:shrinkwrap_fixture_name) { "npm-shrinkwrap.json" }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "that has relative resolved paths" do
          let(:shrinkwrap_fixture_name) { "relative.json" }

          its(:length) { is_expected.to eq(2) }

          context "with a version specified" do
            describe "the first dependency" do
              subject { top_level_dependencies.first }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("fetch-factory") }
              its(:version) { is_expected.to eq("0.0.1") }
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^0.0.1",
                    file: "package.json",
                    groups: ["dependencies"],
                    source: nil
                  }]
                )
              end
            end
          end
        end
      end

      context "with a yarn.lock" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "yarn.lock",
            content: lockfile_body
          )
        end
        let(:lockfile_body) do
          fixture("yarn_lockfiles", yarn_lock_fixture_name)
        end
        let(:yarn_lock_fixture_name) { "yarn.lock" }

        its(:length) { is_expected.to eq(2) }

        context "with a version specified" do
          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("fetch-factory") }
            its(:version) { is_expected.to eq("0.0.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^0.0.1",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "when a dist-tag is specified" do
          let(:package_json_fixture_name) { "dist_tag.json" }
          let(:yarn_lock_fixture_name) { "dist_tag.lock" }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("npm") }
            its(:version) { is_expected.to eq("5.8.0") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "next",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with only dev dependencies" do
          let(:package_json_fixture_name) { "only_dev_dependencies.json" }
          let(:yarn_lock_fixture_name) { "only_dev_dependencies.lock" }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.0") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with an optional dependency" do
          let(:package_json_fixture_name) { "optional_dependencies.json" }

          its(:length) { is_expected.to eq(2) }

          describe "the last dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.7.0") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["optionalDependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with a resolution" do
          let(:package_json_fixture_name) { "resolutions.json" }
          let(:yarn_lock_fixture_name) { "resolutions.lock" }

          its(:length) { is_expected.to eq(1) }

          describe "the first dependency" do
            subject(:dependency) { top_level_dependencies.first }

            # Resolutions affect sub-dependencies, *not* top-level dependencies.
            # The parsed version should therefore be 0.1.0, *not* 1.0.0.
            it "has the right details" do
              expect(dependency).to be_a(Dependabot::Dependency)
              expect(dependency.name).to eq("lodash")
              expect(dependency.version).to eq("0.1.0")
              expect(dependency.requirements).to eq(
                [{
                  requirement: "^0.1.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "that specifies a semver requirement" do
          let(:package_json_fixture_name) do
            "github_dependency_yarn_semver.json"
          end
          let(:yarn_lock_fixture_name) { "github_dependency_yarn_semver.lock" }

          its(:length) { is_expected.to eq(1) }

          describe "the github dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }
            its(:version) { is_expected.to eq("2.0.2") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number",
                    branch: nil,
                    ref: "master"
                  }
                }]
              )
            end
          end

          context "with #semver:" do
            let(:package_json_fixture_name) { "github_dependency_semver.json" }
            let(:yarn_lock_fixture_name) { "github_dependency_semver.lock" }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) { is_expected.to eq("2.0.2") }
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: "^2.0.0",
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end
          end
        end

        context "with a private-source dependency" do
          let(:package_json_fixture_name) { "private_source.json" }
          let(:yarn_lock_fixture_name) { "private_source.lock" }

          its(:length) { is_expected.to eq(7) }

          describe "the second dependency" do
            subject { top_level_dependencies[1] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("chalk") }
            its(:version) { is_expected.to eq("2.3.0") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: {
                    type: "private_registry",
                    url: "http://registry.npm.taobao.org"
                  }
                }]
              )
            end
          end

          describe "the third dependency" do
            subject { top_level_dependencies[2] }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("@dependabot/etag") }
            its(:version) { is_expected.to eq("1.8.0") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^1.0.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "private_registry",
                    url: "https://npm.fury.io/dependabot"
                  }
                }]
              )
            end
          end
        end

        context "with a path-based dependency" do
          let(:files) { [package_json, lockfile, path_dep] }
          let(:package_json_fixture_name) { "path_dependency.json" }
          let(:yarn_lock_fixture_name) { "path_dependency.lock" }
          let(:path_dep) do
            Dependabot::DependencyFile.new(
              name: "deps/etag/package.json",
              content: fixture("package_files", "etag.json"),
              support_file: true
            )
          end

          it "doesn't include the path-based dependency" do
            expect(top_level_dependencies.length).to eq(3)
            expect(top_level_dependencies.map(&:name)).to_not include("etag")
          end
        end

        context "with a symlinked dependency" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "symlinked_dependency.json" }
          let(:yarn_lock_fixture_name) { "symlinked_dependency.lock" }

          it "doesn't include the link dependency" do
            expect(top_level_dependencies.length).to eq(3)
            expect(top_level_dependencies.map(&:name)).to_not include("etag")
          end
        end

        context "with an aliased dependency" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "aliased_dependency.json" }
          let(:yarn_lock_fixture_name) { "aliased_dependency.lock" }

          it "doesn't include the aliased dependency" do
            expect(top_level_dependencies.length).to eq(1)
            expect(top_level_dependencies.map(&:name)).to eq(["etag"])
            expect(dependencies.map(&:name)).to_not include("my-fetch-factory")
          end
        end

        context "with an aliased dependency name (only supported by yarn)" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "aliased_dependency_name.json" }
          let(:yarn_lock_fixture_name) { "aliased_dependency_name.lock" }

          it "doesn't include the aliased dependency" do
            expect(top_level_dependencies.length).to eq(1)
            expect(top_level_dependencies.map(&:name)).to eq(["etag"])
            expect(dependencies.map(&:name)).to_not include("my-fetch-factory")
          end
        end

        context "with a git dependency" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "git_dependency.json" }
          let(:yarn_lock_fixture_name) { "git_dependency.lock" }

          its(:length) { is_expected.to eq(4) }

          describe "the git dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("is-number") }
            its(:version) do
              is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
            end
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: nil,
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: {
                    type: "git",
                    url: "https://github.com/jonschlinkert/is-number.git",
                    branch: nil,
                    ref: "master"
                  }
                }]
              )
            end

            context "when the lockfile entry's requirement is outdated" do
              let(:yarn_lock_fixture_name) do
                "git_dependency_outdated_req.lock"
              end

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) do
                is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
              end
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/jonschlinkert/is-number.git",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end
          end

          context "with a github dependency" do
            let(:package_json_fixture_name) { "github_dependency_slash.json" }
            let(:yarn_lock_fixture_name) { "github_dependency_slash.lock" }

            its(:length) { is_expected.to eq(1) }

            describe "the github dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("bull-arena") }
              its(:version) do
                is_expected.to eq("717ae633af6429206bdc57ce994ce7e45ac48a8e")
              end
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["dependencies"],
                    source: {
                      type: "git",
                      url: "https://github.com/bee-queue/arena",
                      branch: nil,
                      ref: "717ae633af6429206bdc57ce994ce7e45ac48a8e"
                    }
                  }]
                )
              end
            end
          end

          context "with auth details" do
            let(:package_json_fixture_name) { "git_dependency_with_auth.json" }
            let(:yarn_lock_fixture_name) { "git_dependency_with_auth.lock" }

            describe "the git dependency" do
              subject { top_level_dependencies.last }

              it { is_expected.to be_a(Dependabot::Dependency) }
              its(:name) { is_expected.to eq("is-number") }
              its(:version) do
                is_expected.to eq("af885e2e890b9ef0875edd2b117305119ee5bdc5")
              end
              its(:requirements) do
                is_expected.to eq(
                  [{
                    requirement: nil,
                    file: "package.json",
                    groups: ["devDependencies"],
                    source: {
                      type: "git",
                      url: "https://username:password@github.com/"\
                           "jonschlinkert/is-number.git",
                      branch: nil,
                      ref: "master"
                    }
                  }]
                )
              end
            end

            context "specified with https and a colon (supported by npm)" do
              let(:package_json_fixture_name) do
                "git_dependency_with_auth_2.json"
              end
              let(:files) { [package_json] }

              describe "the git dependency" do
                subject { top_level_dependencies.last }

                its(:requirements) do
                  is_expected.to eq(
                    [{
                      requirement: nil,
                      file: "package.json",
                      groups: ["devDependencies"],
                      source: {
                        type: "git",
                        url: "https://username:password@github.com/"\
                             "jonschlinkert/is-number.git",
                        branch: nil,
                        ref: "master"
                      }
                    }]
                  )
                end
              end
            end
          end
        end

        context "with a git source that comes from a sub-dependency" do
          let(:files) { [package_json, lockfile] }
          let(:package_json_fixture_name) { "git_dependency_from_subdep.json" }
          let(:yarn_lock_fixture_name) { "git_dependency_from_subdep.lock" }

          describe "the chalk dependency" do
            subject { dependencies.find { |d| d.name == "chalk" } }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:version) { is_expected.to eq("2.4.1") }
            its(:requirements) do
              is_expected.to eq(
                [{
                  requirement: "^2.0.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with workspaces" do
          let(:package_json_fixture_name) { "workspaces.json" }
          let(:yarn_lock_fixture_name) { "workspaces.lock" }
          let(:files) { [package1, package_json, lockfile, other_package] }
          let(:package1) do
            Dependabot::DependencyFile.new(
              name: "packages/package1/package.json",
              content: fixture("package_files", "package1.json")
            )
          end
          let(:other_package) do
            Dependabot::DependencyFile.new(
              name: "other_package/package.json",
              content: fixture("package_files", "other_package.json")
            )
          end

          its(:length) { is_expected.to eq(3) }

          describe "the last dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.1") }
            its(:requirements) do
              is_expected.to match_array(
                [{
                  requirement: "^1.1.0",
                  file: "packages/package1/package.json",
                  groups: ["devDependencies"],
                  source: nil
                }, {
                  requirement: "^1.0.0",
                  file: "other_package/package.json",
                  groups: ["devDependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "the duplicated dependency" do
            subject { top_level_dependencies.find { |d| d.name == "lodash" } }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("lodash") }
            its(:version) { is_expected.to eq("1.2.0") }
            its(:requirements) do
              is_expected.to match_array(
                [{
                  requirement: "1.2.0",
                  file: "package.json",
                  groups: ["dependencies"],
                  source: nil
                }, {
                  requirement: "^1.2.1",
                  file: "other_package/package.json",
                  groups: ["dependencies"],
                  source: nil
                }, {
                  requirement: "^1.2.1",
                  file: "packages/package1/package.json",
                  groups: ["dependencies"],
                  source: nil
                }]
              )
            end
          end
        end

        context "with lerna.json" do
          let(:files) do
            [
              package_json,
              lerna_json,
              package1,
              package1_lock,
              other_package_json,
              other_package_lock
            ]
          end
          let(:package_json_fixture_name) { "lerna.json" }
          let(:lerna_json) do
            Dependabot::DependencyFile.new(
              name: "lerna.json",
              content: fixture("lerna", "lerna.json")
            )
          end
          let(:package1) do
            Dependabot::DependencyFile.new(
              name: "packages/package1/package.json",
              content: fixture("package_files", "package1.json")
            )
          end
          let(:package1_lock) do
            Dependabot::DependencyFile.new(
              name: "packages/package1/yarn.lock",
              content: fixture("yarn_lockfiles", "package1.lock")
            )
          end
          let(:other_package_json) do
            Dependabot::DependencyFile.new(
              name: "packages/other_package/package.json",
              content:
                fixture("package_files", "other_package.json")
            )
          end
          let(:other_package_lock) do
            Dependabot::DependencyFile.new(
              name: "packages/other_package/yarn.lock",
              content:
                fixture("yarn_lockfiles", "other_package.lock")
            )
          end

          its(:length) { is_expected.to eq(4) }

          describe "the first dependency" do
            subject { top_level_dependencies.first }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("lerna") }
            its(:version) { is_expected.to be_nil }
            its(:requirements) do
              is_expected.to match_array(
                [{
                  requirement: "^3.6.0",
                  file: "package.json",
                  groups: ["devDependencies"],
                  source: nil
                }]
              )
            end
          end

          describe "the last dependency" do
            subject { top_level_dependencies.last }

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("etag") }
            its(:version) { is_expected.to eq("1.8.0") }
            its(:requirements) do
              is_expected.to match_array(
                [{
                  requirement: "^1.1.0",
                  file: "packages/package1/package.json",
                  groups: ["devDependencies"],
                  source: nil
                }, {
                  requirement: "^1.0.0",
                  file: "packages/other_package/package.json",
                  groups: ["devDependencies"],
                  source: nil
                }]
              )
            end
          end
        end
      end
    end

    describe "sub-dependencies" do
      subject(:subdependencies) { dependencies.reject(&:top_level?) }

      context "with a yarn.lock" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "yarn.lock",
            content: lockfile_body
          )
        end
        let(:lockfile_body) do
          fixture("yarn_lockfiles", yarn_lock_fixture_name)
        end
        let(:package_json_fixture_name) { "no_lockfile_change.json" }
        let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

        its(:length) { is_expected.to eq(389) }
      end

      context "with a package-lock.json" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: lockfile_body
          )
        end
        let(:lockfile_body) do
          fixture("npm_lockfiles", yarn_lock_fixture_name)
        end
        let(:package_json_fixture_name) { "blank_requirement.json" }
        let(:yarn_lock_fixture_name) { "blank_requirement.json" }

        its(:length) { is_expected.to eq(22) }
      end
    end
  end
end
