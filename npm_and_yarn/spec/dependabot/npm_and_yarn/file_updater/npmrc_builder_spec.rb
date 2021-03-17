# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_updater/npmrc_builder"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::NpmrcBuilder do
  let(:npmrc_builder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_files) { [package_json, yarn_lock] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: fixture("package_files", manifest_fixture_name),
      name: "package.json"
    )
  end
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("yarn_lockfiles", yarn_lock_fixture_name)
    )
  end
  let(:npmrc) do
    Dependabot::DependencyFile.new(
      name: ".npmrc",
      content: fixture("npmrc", npmrc_fixture_name)
    )
  end
  let(:yarnrc) do
    Dependabot::DependencyFile.new(
      name: ".yarnrc",
      content: fixture("yarnrc", yarnrc_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:npmrc_fixture_name) { "auth_token" }
  let(:yarnrc_fixture_name) { "global_registry" }

  describe "#npmrc_content" do
    subject(:npmrc_content) { npmrc_builder.npmrc_content }

    context "with a yarn.lock" do
      let(:dependency_files) { [package_json, yarn_lock] }

      context "with no private sources and no credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }
        it { is_expected.to eq("") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, yarn_lock, npmrc] }

          it "returns the npmrc file unaltered" do
            expect(npmrc_content).
              to eq(fixture("npmrc", npmrc_fixture_name))
          end

          context "that needs an authToken sanitizing" do
            let(:npmrc_fixture_name) { "env_auth_token" }

            it "removes the env variable use" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
            end
          end

          context "that needs an auth sanitizing" do
            let(:npmrc_fixture_name) { "env_auth" }

            it "removes the env variable use" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
            end
          end
        end

        context "and a yarnrc file" do
          let(:dependency_files) { [package_json, yarn_lock, yarnrc] }

          it "uses the yarnrc file registry" do
            expect(npmrc_content).to eq(
              "registry = https://npm-proxy.fury.io/password/dependabot/\n"
            )
          end
        end
      end

      context "with no private sources and some credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "my_token"
          }]
        end
        it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

        context "that uses basic auth" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "my:token"
            }]
          end
          it "includes Basic auth details" do
            expect(npmrc_content).to eq(
              "always-auth = true\n//registry.npmjs.org/:_auth=bXk6dG9rZW4="
            )
          end
        end

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, yarn_lock, npmrc] }

          it "appends to the npmrc file" do
            expect(npmrc_content).
              to include(fixture("npmrc", npmrc_fixture_name))
            expect(npmrc_content).
              to end_with("\n\n//registry.npmjs.org/:_authToken=my_token")
          end
        end
      end

      context "with no private sources and credentials cleared" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "yarn.lock" }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com"
          }, {
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org"
          }]
        end

        it { is_expected.to eq("") }
      end

      context "with a private source used for some dependencies" do
        let(:manifest_fixture_name) { "private_source.json" }
        let(:yarn_lock_fixture_name) { "private_source.lock" }
        it { is_expected.to eq("") }

        context "and some credentials" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "my_token"
            }]
          end
          it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

          context "where the registry has a trailing slash" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }, {
                "type" => "npm_registry",
                "registry" => "artifactory.jfrog.com"\
                              "/artifactory/api/npm/dependabot/",
                "token" => "my_token"
              }]
            end

            it "only adds a single trailing slash" do
              expect(npmrc_content).
                to eq("//artifactory.jfrog.com/"\
                      "artifactory/api/npm/dependabot/:_authToken=my_token")
            end
          end

          context "that match a scoped package" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }, {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "my_token"
              }, {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dep",
                "token" => "my_other_token"
              }]
            end

            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token\n"\
                      "//npm.fury.io/dep/:_authToken=my_other_token")
            end

            context "using bintray" do
              let(:credentials) do
                [{
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }, {
                  "type" => "npm_registry",
                  "registry" => "api.bintray.com/npm/dependabot/npm-private",
                  "token" => "my_token"
                }]
              end

              it "adds auth details, and scopes them correctly" do
                expect(npmrc_content).
                  to eq(
                    "@dependabot:registry=https://api.bintray.com/npm/"\
                    "dependabot/npm-private/\n"\
                    "//api.bintray.com/npm/dependabot/"\
                    "npm-private/:_authToken=my_token"
                  )
              end
            end

            context "with an irrelevant package-lock.json" do
              let(:dependency_files) { [package_json, yarn_lock, package_lock] }
              let(:npm_lock_fixture_name) { "no_dependencies.json" }

              it "adds auth details, and scopes them correctly" do
                expect(npmrc_content).
                  to eq(
                    "@dependabot:registry=https://npm.fury.io/dependabot/\n"\
                    "//npm.fury.io/dependabot/:_authToken=my_token\n"\
                    "//npm.fury.io/dep/:_authToken=my_other_token"
                  )
              end
            end
          end
        end
      end

      context "with a private source used for some deps and creds cleared" do
        let(:manifest_fixture_name) { "private_source.json" }
        let(:yarn_lock_fixture_name) { "private_source.lock" }

        context "and some credentials" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com"
            }, {
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org"
            }]
          end
          it { is_expected.to eq("") }
        end

        context "that match a scoped package" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dep"
            }]
          end
          it "adds auth details, and scopes them correctly" do
            expect(npmrc_content).
              to eq("@dependabot:registry=https://npm.fury.io/dependabot/")
          end
        end
      end

      context "with a private source used for all dependencies" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "all_private.lock" }
        it { is_expected.to eq("") }

        context "and credentials for the private source" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot",
              "token" => "my_token"
            }]
          end

          it "adds a global registry line, and auth details" do
            expect(npmrc_content).
              to eq("registry = https://npm.fury.io/dependabot\n"\
                    "_authToken = my_token\n"\
                    "always-auth = true\n"\
                    "//npm.fury.io/dependabot/:_authToken=my_token")
          end

          context "and an npmrc file" do
            let(:dependency_files) { [package_json, yarn_lock, npmrc] }
            let(:npmrc_fixture_name) { "env_global_auth" }

            it "extends the already existing npmrc" do
              expect(npmrc_content).
                to eq("always-auth = true\n"\
                      "strict-ssl = true\n"\
                      "//npm.fury.io/dependabot/:_authToken=secret_token\n"\
                      "registry = https://npm.fury.io/dependabot\n"\
                      "_authToken = my_token\n"\
                      "always-auth = true\n\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end

            context "that uses environment variables everywhere" do
              let(:npmrc_fixture_name) { "env_registry" }

              it "extends the already existing npmrc" do
                expect(npmrc_content).
                  to eq("//dependabot.jfrog.io/dependabot/api/npm/"\
                        "platform-npm/:always-auth=true\n"\
                        "always-auth = true\n"\
                        "registry = https://npm.fury.io/dependabot\n"\
                        "_authToken = my_token\n"\
                        "always-auth = true\n\n"\
                        "//npm.fury.io/dependabot/:_authToken=my_token")
              end
            end
          end

          context "and a yarnrc file" do
            let(:dependency_files) { [package_json, yarn_lock, yarnrc] }

            it "uses the yarnrc file registry" do
              expect(npmrc_content).to eq(
                "registry = https://npm-proxy.fury.io/password/dependabot/\n\n"\
                "//npm.fury.io/dependabot/:_authToken=my_token"
              )
            end

            context "that doesn't contain details of the registry" do
              let(:yarnrc_fixture_name) { "offline_mirror" }

              it "adds a global registry line based on the lockfile details" do
                expect(npmrc_content).
                  to eq("registry = https://npm.fury.io/dependabot\n"\
                        "_authToken = my_token\n"\
                        "always-auth = true\n"\
                        "//npm.fury.io/dependabot/:_authToken=my_token")
              end
            end
          end
        end
      end

      context "with a private source used for all deps with creds cleared" do
        let(:manifest_fixture_name) { "package.json" }
        let(:yarn_lock_fixture_name) { "all_private.lock" }
        it { is_expected.to eq("") }

        context "and credentials for the private source" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            }]
          end

          it "adds a global registry line, and auth details" do
            expect(npmrc_content).
              to eq("registry = https://npm.fury.io/dependabot\n"\
                    "always-auth = true")
          end

          context "and an npmrc file" do
            let(:dependency_files) { [package_json, yarn_lock, npmrc] }
            let(:npmrc_fixture_name) { "env_global_auth" }

            it "extends the already existing npmrc" do
              expect(npmrc_content).
                to eq("always-auth = true\n"\
                      "strict-ssl = true\n"\
                      "//npm.fury.io/dependabot/:_authToken=secret_token\n"\
                      "registry = https://npm.fury.io/dependabot\n"\
                      "always-auth = true\n")
            end

            context "that uses environment variables everywhere" do
              let(:npmrc_fixture_name) { "env_registry" }

              it "extends the already existing npmrc" do
                expect(npmrc_content).
                  to eq("//dependabot.jfrog.io/dependabot/api/npm/"\
                        "platform-npm/:always-auth=true\n"\
                        "always-auth = true\n"\
                        "registry = https://npm.fury.io/dependabot\n"\
                        "always-auth = true\n")
              end
            end
          end

          context "and a yarnrc file" do
            let(:dependency_files) { [package_json, yarn_lock, yarnrc] }

            it "uses the yarnrc file registry" do
              expect(npmrc_content).to eq(
                "registry = https://npm-proxy.fury.io/password/dependabot/\n"
              )
            end

            context "that doesn't contain details of the registry" do
              let(:yarnrc_fixture_name) { "offline_mirror" }

              it "adds a global registry line based on the lockfile details" do
                expect(npmrc_content).
                  to eq("registry = https://npm.fury.io/dependabot\n"\
                        "always-auth = true")
              end
            end
          end
        end
      end
    end

    context "with a package-lock.json" do
      let(:dependency_files) { [package_json, package_lock] }

      context "with no private sources and no credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "package-lock.json" }
        it { is_expected.to eq("") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, package_lock, npmrc] }

          it "returns the npmrc file unaltered" do
            expect(npmrc_content).
              to eq(fixture("npmrc", npmrc_fixture_name))
          end

          context "that need sanitizing" do
            let(:npmrc_fixture_name) { "env_auth_token" }

            it "removes the env variable use" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
            end
          end
        end
      end

      context "with no private sources and some credentials" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "package-lock.json" }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "my_token"
          }]
        end
        it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, package_lock, npmrc] }

          it "appends to the npmrc file" do
            expect(npmrc_content).
              to include(fixture("npmrc", npmrc_fixture_name))
            expect(npmrc_content).
              to end_with("\n\n//registry.npmjs.org/:_authToken=my_token")
          end
        end
      end

      context "with no private sources and credentials cleared" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "package-lock.json" }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com"
          }, {
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org"
          }]
        end
        it { is_expected.to eq("") }

        context "and an npmrc file" do
          let(:dependency_files) { [package_json, package_lock, npmrc] }

          it "does not append to the npmrc file" do
            expect(npmrc_content).
              to eq(fixture("npmrc", npmrc_fixture_name))
          end
        end
      end

      context "with a private source used for some dependencies" do
        let(:manifest_fixture_name) { "private_source.json" }
        let(:npm_lock_fixture_name) { "private_source.json" }
        it { is_expected.to eq("") }

        context "and some credentials" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org",
              "token" => "my_token"
            }]
          end
          it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

          context "that match a scoped package" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }, {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "my_token"
              }]
            end
            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end
          end
        end
      end

      context "with a private source used for some deps and creds cleared" do
        let(:manifest_fixture_name) { "private_source.json" }
        let(:npm_lock_fixture_name) { "private_source.json" }
        it { is_expected.to eq("") }

        context "and some credentials" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com"
            }, {
              "type" => "npm_registry",
              "registry" => "registry.npmjs.org"
            }]
          end
          it { is_expected.to eq("") }

          context "that match a scoped package" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "github.com"
              }, {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot"
              }]
            end
            it "adds auth details, and scopes them correctly" do
              expect(npmrc_content).
                to eq("@dependabot:registry=https://npm.fury.io/dependabot/")
            end
          end
        end
      end

      context "with a private source used for all dependencies" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "all_private.json" }
        it { is_expected.to eq("") }

        context "and credentials for the private source" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot",
              "token" => "my_token"
            }]
          end

          it "adds a global registry line, and token auth details" do
            expect(npmrc_content).
              to eq("registry = https://npm.fury.io/dependabot\n"\
                    "_authToken = my_token\n"\
                    "always-auth = true\n"\
                    "//npm.fury.io/dependabot/:_authToken=my_token")
          end

          context "with basic auth credentials" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }, {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "secret:token"
              }]
            end

            it "adds a global registry line, and Basic auth details" do
              expect(npmrc_content).
                to eq("registry = https://npm.fury.io/dependabot\n"\
                      "_auth = c2VjcmV0OnRva2Vu\n"\
                      "always-auth = true\n"\
                      "always-auth = true\n"\
                      "//npm.fury.io/dependabot/:_auth=c2VjcmV0OnRva2Vu")
            end
          end

          context "and an npmrc file" do
            let(:dependency_files) { [package_json, package_lock, npmrc] }
            let(:npmrc_fixture_name) { "env_global_auth" }

            it "populates the already existing npmrc" do
              expect(npmrc_content).
                to eq("always-auth = true\n"\
                      "strict-ssl = true\n"\
                      "//npm.fury.io/dependabot/:_authToken=secret_token\n"\
                      "registry = https://npm.fury.io/dependabot\n"\
                      "_authToken = my_token\n"\
                      "always-auth = true\n\n"\
                      "//npm.fury.io/dependabot/:_authToken=my_token")
            end

            context "with basic auth credentials" do
              let(:credentials) do
                [{
                  "type" => "git_source",
                  "host" => "github.com",
                  "username" => "x-access-token",
                  "password" => "token"
                }, {
                  "type" => "npm_registry",
                  "registry" => "npm.fury.io/dependabot",
                  "token" => "secret:token"
                }]
              end

              it "populates the already existing npmrc" do
                expect(npmrc_content).
                  to eq("always-auth = true\n"\
                        "strict-ssl = true\n"\
                        "//npm.fury.io/dependabot/:_authToken=secret_token\n"\
                        "registry = https://npm.fury.io/dependabot\n"\
                        "_auth = c2VjcmV0OnRva2Vu\n"\
                        "always-auth = true\n\n"\
                        "always-auth = true\n"\
                        "//npm.fury.io/dependabot/:_auth=c2VjcmV0OnRva2Vu")
              end
            end
          end
        end
      end

      context "with a private source used for all deps and creds cleared" do
        let(:manifest_fixture_name) { "package.json" }
        let(:npm_lock_fixture_name) { "all_private.json" }
        it { is_expected.to eq("") }

        context "and credentials for the private source" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            }]
          end

          it "adds a global registry line, and token auth details" do
            expect(npmrc_content).
              to eq("registry = https://npm.fury.io/dependabot\n"\
                    "always-auth = true")
          end

          context "with basic auth credentials cleared" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "github.com"
              }, {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot"
              }]
            end

            it "adds a global registry line, and Basic auth details" do
              expect(npmrc_content).
                to eq("registry = https://npm.fury.io/dependabot\n"\
                      "always-auth = true")
            end
          end

          context "and an npmrc file" do
            let(:dependency_files) { [package_json, package_lock, npmrc] }
            let(:npmrc_fixture_name) { "env_global_auth" }

            it "populates the already existing npmrc" do
              expect(npmrc_content).
                to eq("always-auth = true\n"\
                      "strict-ssl = true\n"\
                      "//npm.fury.io/dependabot/:_authToken=secret_token\n"\
                      "registry = https://npm.fury.io/dependabot\n"\
                      "always-auth = true\n")
            end

            context "with basic auth credentials" do
              let(:credentials) do
                [{
                  "type" => "git_source",
                  "host" => "github.com"
                }, {
                  "type" => "npm_registry",
                  "registry" => "npm.fury.io/dependabot"
                }]
              end

              it "populates the already existing npmrc" do
                expect(npmrc_content).
                  to eq("always-auth = true\n"\
                        "strict-ssl = true\n"\
                        "//npm.fury.io/dependabot/:_authToken=secret_token\n"\
                        "registry = https://npm.fury.io/dependabot\n"\
                        "always-auth = true\n")
              end
            end
          end
        end
      end
    end
  end
end
