# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/dep/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Dep::FileParser do
  it_behaves_like "a dependency file parser"

  let(:parser) { described_class.new(dependency_files: files, source: source) }

  let(:files) { [manifest, lockfile] }
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "Gopkg.toml",
      content: fixture("gopkg_tomls", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gopkg.lock",
      content: fixture("gopkg_locks", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "cockroach.toml" }
  let(:lockfile_fixture_name) { "cockroach.lock" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  before do
    stub_request(:get, "https://golang.org/x/text?go-get=1").
      to_return(
        status: 200,
        body: fixture("repo_responses", "golang_org_text.html")
      )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(149) }

    describe "top level dependencies" do
      subject(:dependencies) { parser.parse.select(&:top_level?) }

      its(:length) { is_expected.to eq(9) }

      describe "a regular version dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "github.com/satori/go.uuid" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("github.com/satori/go.uuid")
          expect(dependency.version).to eq("1.2.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "v1.2.0",
              file: "Gopkg.toml",
              groups: [],
              source: {
                type: "default",
                source: "github.com/satori/go.uuid"
              }
            }]
          )
        end

        context "that doesn't declare a version" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "github.com/dgrijalva/jwt-go" }
          end
          let(:manifest_fixture_name) { "no_version.toml" }
          let(:lockfile_fixture_name) { "no_version.lock" }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("github.com/dgrijalva/jwt-go")
            expect(dependency.version).to eq("1.0.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "default",
                  source: "github.com/dgrijalva/jwt-go"
                }
              }]
            )
          end
        end
      end

      context "with a dependency that isn't in the lockfile" do
        let(:manifest_fixture_name) { "unused_constraint.toml" }
        let(:lockfile_fixture_name) { "unused_constraint.lock" }

        its(:length) { is_expected.to eq(1) }

        it "has the right details" do
          expect(dependencies.map(&:name)).
            to eq(["github.com/dgrijalva/jwt-go"])
        end
      end

      describe "a git version dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "golang.org/x/text" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("golang.org/x/text")
          expect(dependency.version).
            to eq("470f45bf29f4147d6fbd7dfd0a02a848e49f5bf4")
          expect(dependency.requirements).to eq(
            [{
              requirement: nil,
              file: "Gopkg.toml",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/golang/text",
                branch: nil,
                ref: "470f45bf29f4147d6fbd7dfd0a02a848e49f5bf4"
              }
            }]
          )
        end

        context "that specifies a tag as its revision" do
          let(:manifest_fixture_name) { "tag_as_revision.toml" }
          let(:lockfile_fixture_name) { "tag_as_revision.lock" }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("golang.org/x/text")
            expect(dependency.version).to eq("v0.2.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/golang/text",
                  branch: nil,
                  ref: "v0.2.0"
                }
              }]
            )
          end
        end

        context "that specifies a tag as its version" do
          let(:manifest_fixture_name) { "tag_as_version.toml" }
          let(:lockfile_fixture_name) { "tag_as_version.lock" }
          subject(:dependency) do
            dependencies.find { |d| d.name == "github.com/globalsign/mgo" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("github.com/globalsign/mgo")
            expect(dependency.version).
              to eq("efe0945164a7e582241f37ae8983c075f8f2e870")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/globalsign/mgo",
                  branch: nil,
                  ref: "r2018.04.23"
                }
              }]
            )
          end
        end

        context "that is missing a version in its manifest and lockfile" do
          let(:manifest_fixture_name) { "missing_version.toml" }
          let(:lockfile_fixture_name) { "missing_version.lock" }
          subject(:dependency) do
            dependencies.find { |d| d.name == "github.com/caarlos0/env" }
          end

          it "is filtered out" do
            expect(dependency).to be_nil
          end
        end

        describe "with a proxy host in the name" do
          let(:manifest_fixture_name) { "proxy_git_source.toml" }
          let(:lockfile_fixture_name) { "proxy_git_source.lock" }
          subject(:dependency) do
            dependencies.find { |d| d.name == "k8s.io/apimachinery" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("k8s.io/apimachinery")
            expect(dependency.version).
              to eq("cbafd24d5796966031ae904aa88e2436a619ae8a")
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "Gopkg.toml",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/kubernetes/apimachinery",
                  branch: "master",
                  ref: nil
                }
              }]
            )
          end

          context "that returns a 404" do
            let(:manifest_fixture_name) { "proxy_git_source_not_found.toml" }
            let(:lockfile_fixture_name) { "proxy_git_source_not_found.lock" }

            it "raises the correct error" do
              expect { parser.parse }.
                to raise_error do |err|
                  expect(err).to be_a(Dependabot::DependencyFileNotResolvable)
                  expect(err.message).
                    to eq("dependabot.com/unknown returned a 404")
                end
            end
          end

          context "that is not resolvable" do
            let(:manifest_fixture_name) { "proxy_git_source_unresolvable.toml" }
            let(:lockfile_fixture_name) { "proxy_git_source_unresolvable.lock" }

            it "raises the correct error" do
              expect { parser.parse }.
                to raise_error do |err|
                  expect(err).to be_a(Dependabot::DependencyFileNotResolvable)
                  expect(err.message).
                    to eq("Cannot detect VCS for unresolvablelkajs.com/unknown")
                end
            end
          end
        end
      end
    end
  end
end
