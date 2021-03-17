# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_fetcher/path_gemspec_finder"

RSpec.describe Dependabot::Bundler::FileFetcher::PathGemspecFinder do
  let(:finder) { described_class.new(gemfile: gemfile) }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: gemfile_name)
  end
  let(:gemfile_name) { "Gemfile" }
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

  describe "#path_gemspec_paths" do
    subject(:path_gemspec_paths) { finder.path_gemspec_paths }

    context "when the file does not include any path gemspecs" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      it { is_expected.to eq([]) }
    end

    context "with invalid Ruby in the Gemfile" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "invalid_ruby") }

      it "raises a helpful error" do
        expect { finder.path_gemspec_paths }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_name).to eq("Gemfile")
        end
      end
    end

    context "when the file does include a path gemspec" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source") }
      it { is_expected.to eq([Pathname.new("plugins/example")]) }

      context "whose path must be eval-ed" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source_eval") }

        it "raises a helpful error" do
          expect { finder.path_gemspec_paths }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotParseable)
            expect(error.file_name).to eq("Gemfile")
          end
        end
      end

      context "when this Gemfile is already in a nested directory" do
        let(:gemfile_name) { "nested/Gemfile" }

        it { is_expected.to eq([Pathname.new("nested/plugins/example")]) }
      end

      context "that is behind a conditional that is false" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source_if") }
        it { is_expected.to eq([Pathname.new("plugins/example")]) }
      end
    end
  end
end
