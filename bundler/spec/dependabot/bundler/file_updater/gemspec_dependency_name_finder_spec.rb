# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/bundler/file_updater/gemspec_dependency_name_finder"

module_to_test = Dependabot::Bundler::FileUpdater
RSpec.describe module_to_test::GemspecDependencyNameFinder do
  let(:finder) { described_class.new(gemspec_content: gemspec_content) }
  let(:gemspec_content) { fixture("ruby", "gemspecs", "small_example") }

  describe "#dependency_name" do
    subject(:dependency_name) { finder.dependency_name }

    it { is_expected.to eq("example") }

    context "with an unevaluatable gemspec name" do
      let(:gemspec_content) { fixture("ruby", "gemspecs", "function_name") }
      it { is_expected.to be_nil }
    end
  end
end
