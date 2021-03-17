# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"

RSpec.describe Dependabot::DependencyFile do
  let(:file) { described_class.new(name: "Gemfile", content: "a") }

  describe "#path" do
    subject { file.path }

    context "without a directory specified" do
      it { is_expected.to eq("/Gemfile") }
    end

    context "with a directory specified" do
      let(:file) do
        described_class.new(name: "Gemfile", content: "a", directory: directory)
      end

      context "that starts and ends with a slash" do
        let(:directory) { "/path/to/files/" }
        it { is_expected.to eq("/path/to/files/Gemfile") }
      end

      context "that doesn't start or end with a slash" do
        let(:directory) { "path/to/files" }
        it { is_expected.to eq("/path/to/files/Gemfile") }
      end

      context "when the filename includes a '..'" do
        let(:directory) { "path/to/files" }
        let(:file) do
          described_class.new(
            name: "../Gemfile",
            content: "a",
            directory: directory
          )
        end
        it { is_expected.to eq("/path/to/Gemfile") }
      end
    end
  end

  describe "#directory" do
    subject { file.directory }

    context "without a directory specified" do
      it { is_expected.to eq("/") }
    end

    context "with a directory specified" do
      let(:file) do
        described_class.new(name: "Gemfile", content: "a", directory: directory)
      end

      context "that starts and ends with a slash" do
        let(:directory) { "/path/to/files" }
        it { is_expected.to eq("/path/to/files") }
      end

      context "that doesn't start or end with a slash" do
        let(:directory) { "path/to/files" }
        it { is_expected.to eq("/path/to/files") }
      end
    end
  end

  describe "#to_h" do
    subject { file.to_h }

    context "with a non-symlink" do
      it "returns the correct array" do
        expect(subject).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false
        )
      end
    end

    context "with a symlink" do
      let(:file) do
        described_class.new(
          name: "Gemfile",
          content: "a",
          type: "symlink",
          symlink_target: "nested/Gemfile"
        )
      end

      it "returns the correct array" do
        expect(subject).to eq(
          "name" => "Gemfile",
          "content" => "a",
          "directory" => "/",
          "type" => "symlink",
          "support_file" => false,
          "symlink_target" => "nested/Gemfile",
          "content_encoding" => "utf-8",
          "deleted" => false
        )
      end
    end
  end

  describe "#==" do
    context "when two dependency files are equal" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) { described_class.new(name: "Gemfile", content: "a") }

      specify { expect(file1).to eq(file2) }
    end

    context "when two dependency files are equal, but one is a support file" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) do
        described_class.new(name: "Gemfile", content: "a", support_file: true)
      end

      specify { expect(file1).to eq(file2) }
    end

    context "when two dependency files are not equal" do
      let(:file1) { described_class.new(name: "Gemfile", content: "a") }
      let(:file2) { described_class.new(name: "Gemfile", content: "b") }

      specify { expect(file1).to_not eq(file2) }
    end
  end

  describe "#decoded_content" do
    context "for base64 encoded content" do
      let(:file) do
        described_class.new(
          name: "example.gem",
          content_encoding: described_class::ContentEncoding::BASE64,
          content: "YWJj\n"
        )
      end

      it "decodes the content to its original encoding" do
        expect(file.decoded_content).to eq("abc")
      end
    end

    context "for utf-8 encoded content" do
      let(:file) do
        described_class.new(
          name: "example.gem",
          content: "abc"
        )
      end

      it "returns the unencoded content" do
        expect(file.decoded_content).to eq("abc")
      end
    end
  end
end
