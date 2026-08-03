# frozen_string_literal: true

require "spec_helper"
require "rutidy/formatter"
require "rspec/core/sandbox"
require "stringio"

# Runs a real, isolated RSpec suite (via RSpec::Core::Sandbox -- the same
# mechanism rspec-core's own spec suite uses to test its built-in formatters,
# see spec/support/formatter_support.rb upstream) through Formatter, then
# inspects the JSON it actually produced. This is the whole point of writing
# a real formatter instead of parsing text after the fact: there's no
# hierarchy-reconstruction heuristic here to get subtly wrong, so the tests
# below are about confirming the notification wiring is correct, not about
# disambiguation edge cases the way xctidy's comma-splitting specs are.
RSpec.describe Rutidy::Formatter do
  around do |example|
    RSpec::Core::Sandbox.sandboxed { example.run }
  end

  def captured_examples
    output = StringIO.new
    config = RSpec.configuration
    config.output_stream = output
    config.formatter_loader.add(described_class, output)
    reporter = config.reporter

    root = RSpec.describe("Calculator") do
      context "addition" do
        it("adds two positive numbers") { expect(1 + 1).to eq(2) }
        it("adds a negative number") { expect(1 + -1).to eq(99) }
      end

      context "subtraction", skip: "not implemented yet" do
        it("is skipped for now") {}
      end
    end

    root.run(reporter)
    formatter = config.formatters.first
    formatter.close(nil)

    JSON.parse(output.string, symbolize_names: true).fetch(:examples)
  end

  it "captures each example's real nesting as a hierarchy array" do
    examples = captured_examples

    expect(examples[0][:hierarchy]).to eq(["Calculator", "addition", "adds two positive numbers"])
    expect(examples[1][:hierarchy]).to eq(["Calculator", "addition", "adds a negative number"])
    expect(examples[2][:hierarchy]).to eq(["Calculator", "subtraction", "is skipped for now"])
  end

  it "reports each example's real status" do
    examples = captured_examples

    expect(examples[0][:status]).to eq("passed")
    expect(examples[1][:status]).to eq("failed")
    expect(examples[2][:status]).to eq("pending")
  end

  it "attaches the exception class and message on a failure" do
    examples = captured_examples

    exception = examples[1][:exception]
    expect(exception[:class]).to eq("RSpec::Expectations::ExpectationNotMetError")
    expect(exception[:message]).to include("expected: 99")
  end

  it "attaches the pending message on a pending example" do
    examples = captured_examples

    expect(examples[2][:pending_message]).to eq("not implemented yet")
  end
end
