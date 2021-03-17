# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/elm/update_checker/elm_18_version_resolver"

namespace = Dependabot::Elm::UpdateChecker
RSpec.describe namespace::Elm18VersionResolver do
  def elm_version(version_string)
    Dependabot::Elm::Version.new(version_string)
  end

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      candidate_versions: candidate_versions
    )
  end
  let(:unlock_requirement) { :none }
  let(:dependency_files) { [elm_package] }
  let(:candidate_versions) { [elm_version("13.1.1"), elm_version("14.0.0")] }
  let(:elm_package) do
    Dependabot::DependencyFile.new(
      name: "elm-package.json",
      content: fixture("elm_packages", fixture_name)
    )
  end
  let(:fixture_name) { "version_resolver_one_simple_dep" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "elm"
    )
  end
  let(:dependency_name) { "rtfeldman/elm-css" }
  let(:dependency_version) { "13.1.1" }
  let(:dependency_requirements) do
    [{
      file: "elm-package.json",
      requirement: dependency_requirement,
      groups: [],
      source: nil
    }]
  end
  let(:dependency_requirement) { "13.1.1 <= v <= 13.1.1" }

  describe "#latest_resolvable_version" do
    subject do
      resolver.latest_resolvable_version(unlock_requirement: unlock_requirement)
    end

    context "allowing :none unlocks" do
      let(:unlock_requirement) { :none }
      it { is_expected.to eq(elm_version(dependency_version)) }

      context "without a version" do
        let(:dependency_version) { nil }
        let(:dependency_requirement) { "12.1.1 <= v < 14.0.0" }

        it { is_expected.to be_nil }
      end
    end

    context "1) clean bump" do
      let(:dependency_version) { "13.1.1" }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version("14.0.0")) }

        context "without a version" do
          let(:dependency_version) { nil }
          let(:dependency_requirement) { "11.1.1 <= v < 13.0.0" }

          it { is_expected.to eq(elm_version("14.0.0")) }
        end
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version("14.0.0")) }

        context "without a version" do
          let(:dependency_version) { nil }
          let(:dependency_requirement) { "11.1.1 <= v < 13.0.0" }

          it { is_expected.to eq(elm_version("14.0.0")) }
        end
      end
    end

    context "2) forced full unlock" do
      let(:fixture_name) { "elm_css_and_datetimepicker" }
      let(:dependency_name) { "NoRedInk/datetimepicker" }
      let(:dependency_requirement) { "3.0.1 <= v <= 3.0.1" }
      let(:dependency_version) { "3.0.1" }
      let(:candidate_versions) { [elm_version("3.0.1"), elm_version("3.0.2")] }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version("3.0.1")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version("3.0.2")) }

        context "without a version" do
          let(:fixture_name) { "elm_css_and_datetimepicker_ranges" }
          let(:dependency_version) { nil }
          let(:dependency_requirement) { "3.0.0 <= v <= 3.0.1" }
          it { is_expected.to eq(elm_version("3.0.2")) }
        end
      end
    end

    context "3) downgrade bug" do
      let(:fixture_name) { "elm_css_and_datetimepicker" }
      let(:dependency_name) { "rtfeldman/elm-css" }
      let(:dependency_requirement) { "13.1.1 <= v <= 13.1.1" }
      let(:dependency_version) { "13.1.1" }
      let(:candidate_versions) do
        [elm_version("13.1.1"), elm_version("14.0.0")]
      end

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version("13.1.1")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version("13.1.1")) }
      end
    end

    context "3) a <= v < b that doesn't require :own unlock" do
      let(:fixture_name) { "version_resolver_one_dep_lower_than" }
      let(:dependency_version) { elm_version("14.0.0") }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version(elm_version("14.0.0"))) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version(elm_version("14.0.0"))) }
      end
    end

    context "4) empty elm-stuff bug means we don't bump" do
      let(:fixture_name) { "version_resolver_one_dep_lower_than" }
      let(:dependency_version) { elm_version("14.0.0") }
      let(:candidate_versions) { [elm_version("999.1.1")] }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version(elm_version("14.0.0"))) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version(elm_version("14.0.0"))) }
      end
    end

    context "5) dependencies too far apart" do
      let(:fixture_name) { "version_resolver_elm_package_error" }
      let(:dependency_version) { "13.1.1" }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to include("I cannot find a set of packages that works")
            end
        end
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to include("I cannot find a set of packages that works")
            end
        end
      end
    end

    context "5) old version of elm" do
      let(:fixture_name) { "old_elm" }
      let(:dependency_name) { "elm-lang/core" }
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [{
          file: "elm-package.json",
          requirement: dependency_requirement,
          groups: [],
          source: nil
        }]
      end
      let(:dependency_requirement) { "4.0.0 <= v < 5.0.0" }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to include("You are using Elm 0.18.0, but")
            end
        end
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to include("You are using Elm 0.18.0, but")
            end
        end
      end
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject { resolver.updated_dependencies_after_full_unlock }

    context "2) forced full unlock" do
      let(:fixture_name) { "elm_css_and_datetimepicker" }
      let(:dependency_name) { "NoRedInk/datetimepicker" }
      let(:dependency_requirement) { "3.0.1 <= v <= 3.0.1" }
      let(:dependency_version) { "3.0.1" }
      let(:candidate_versions) { [elm_version("3.0.1"), elm_version("3.0.2")] }

      it "bumps the other dependency too" do
        new_datetimepicker =
          Dependabot::Dependency.new(
            name: dependency_name,
            version: candidate_versions.last.to_s,
            requirements: [{
              requirement: "3.0.2 <= v <= 3.0.2",
              groups: [],
              source: nil,
              file: "elm-package.json"
            }],
            previous_version: dependency_version,
            previous_requirements: [{
              requirement: dependency_requirement,
              groups: [],
              source: nil,
              file: "elm-package.json"
            }],
            package_manager: "elm"
          )
        new_elm_css =
          Dependabot::Dependency.new(
            name: "rtfeldman/elm-css",
            version: "14.0.0",
            requirements: [{
              requirement: "14.0.0 <= v <= 14.0.0",
              groups: [],
              source: nil,
              file: "elm-package.json"
            }],
            previous_version: "13.1.1",
            previous_requirements: [{
              requirement: "13.1.1 <= v <= 13.1.1",
              groups: [],
              source: nil,
              file: "elm-package.json"
            }],
            package_manager: "elm"
          )

        expect(subject).to match_array([new_elm_css, new_datetimepicker])
      end

      context "with a range requirement" do
        let(:fixture_name) { "elm_css_and_datetimepicker_ranges" }
        let(:dependency_name) { "NoRedInk/datetimepicker" }
        let(:dependency_requirement) { "3.0.0 <= v <= 3.0.1" }
        let(:dependency_version) { nil }

        it "bumps the other dependency too" do
          new_datetimepicker =
            Dependabot::Dependency.new(
              name: dependency_name,
              version: candidate_versions.last.to_s,
              requirements: [{
                requirement: "3.0.2 <= v <= 3.0.2",
                groups: [],
                source: nil,
                file: "elm-package.json"
              }],
              previous_version: dependency_version,
              previous_requirements: [{
                requirement: dependency_requirement,
                groups: [],
                source: nil,
                file: "elm-package.json"
              }],
              package_manager: "elm"
            )
          new_elm_css =
            Dependabot::Dependency.new(
              name: "rtfeldman/elm-css",
              version: "14.0.0",
              requirements: [{
                requirement: "14.0.0 <= v <= 14.0.0",
                groups: [],
                source: nil,
                file: "elm-package.json"
              }],
              previous_version: nil,
              previous_requirements: [{
                requirement: "13.1.0 <= v <= 13.1.1",
                groups: [],
                source: nil,
                file: "elm-package.json"
              }],
              package_manager: "elm"
            )

          expect(subject).to match_array([new_elm_css, new_datetimepicker])
        end
      end
    end
  end
end
