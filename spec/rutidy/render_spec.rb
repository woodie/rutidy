# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Rutidy::Render do
  def sample_examples
    [
      { hierarchy: %w[Calculator addition] + ["adds two positive numbers"], status: "passed",
        run_time: 0.001, file_path: "./spec/calculator_spec.rb" },
      { hierarchy: %w[Calculator addition] + ["adds a negative number"], status: "failed",
        run_time: 0.002, file_path: "./spec/calculator_spec.rb",
        exception: { class: "RSpec::Expectations::ExpectationNotMetError",
                     message: "expected: 4\n     got: 3", backtrace: ["./spec/calculator_spec.rb:12"] } },
      { hierarchy: %w[Calculator subtraction] + ["is skipped for now"], status: "pending",
        run_time: 0.0, file_path: "./spec/calculator_spec.rb", pending_message: "Temporarily skipped with xit" },
    ]
  end

  def render(examples, style: :classic, color: false)
    out = StringIO.new
    failed = described_class.call(examples, style: style, out: out, color: color)
    [failed, out.string]
  end

  context "a suite has a pass, a fail, and a pending example" do
    it "reports one failed example" do
      failed, = render(sample_examples)
      expect(failed).to eq(1)
    end

    it "prints the top-level group flush left, with a leading blank line" do
      _, out = render(sample_examples)
      expect(out).to start_with("\nCalculator\n  addition\n")
    end

    it "prints the shared context path once, not once per leaf" do
      _, out = render(sample_examples)
      tree, = out.split("Failures:")
      expect(tree.scan("Calculator").length).to eq(1)
      expect(tree.scan("addition").length).to eq(1)
    end

    it "ends with the shared footer" do
      _, out = render(sample_examples)
      expect(out).to include("Test Failed\n")
      expect(out).to include("Tests Passed: 1 failed, 1 pending, 3 total")
    end

    it "lists the failure with its captured exception" do
      _, out = render(sample_examples)
      expect(out).to include("Failures:")
      expect(out).to include("expected: 4")
    end

    it "marks the failing leaf with a FAILED cross-reference" do
      _, out = render(sample_examples)
      expect(out).to include("adds a negative number (FAILED - 1) (0.0020 seconds)")
    end

    it "marks the pending leaf with its elapsed time and no PENDING text" do
      _, out = render(sample_examples)
      expect(out).to include("⊘ is skipped for now (0.0000 seconds)")
      expect(out).not_to include("PENDING")
    end
  end

  context "classic style with color enabled" do
    it "colors only the glyph and the elapsed time on a passing leaf" do
      _, out = render(sample_examples, color: true)
      expect(out).to include("\e[32m✔\e[0m adds two positive numbers (\e[32m0.0010\e[0m seconds)")
    end

    it "colors only the glyph and the elapsed time on a failing leaf" do
      _, out = render(sample_examples, color: true)
      expect(out).to include("\e[31m✖\e[0m adds a negative number (FAILED - 1) (\e[31m0.0020\e[0m seconds)")
    end
  end

  context "a suite has more than one top-level group" do
    def two_groups
      [
        { hierarchy: %w[Calculator addition] + ["adds two positive numbers"], status: "passed", run_time: 0.001 },
        { hierarchy: %w[Formatter] + ["formats a number"], status: "passed", run_time: 0.001 },
      ]
    end

    it "separates the two top-level groups with a blank line" do
      _, out = render(two_groups)
      expect(out).to include("adds two positive numbers (0.0010 seconds)\n\nFormatter")
    end
  end

  context "every example passes" do
    def clean_examples
      [{ hierarchy: %w[Clean] + ["does the thing"], status: "passed", run_time: 0.001 }]
    end

    it "reports zero failures" do
      failed, = render(clean_examples)
      expect(failed).to eq(0)
    end

    it "closes with Test Succeeded, not Test Failed" do
      _, out = render(clean_examples)
      expect(out).to include("Test Succeeded\n")
    end

    it "omits the Failures section entirely" do
      _, out = render(clean_examples)
      expect(out).not_to include("Failures:")
    end
  end

  context "in fd style" do
    it "omits the classic glyph" do
      _, out = render(sample_examples, style: :fd)
      expect(out).not_to include("✔")
      expect(out).not_to include("✖")
    end

    it "labels the pending leaf PENDING with its reason" do
      _, out = render(sample_examples, style: :fd)
      expect(out).to include("is skipped for now (PENDING: Temporarily skipped with xit)")
    end
  end

  context "in fs style" do
    it "uses a checkmark for the passing leaf and grays the name" do
      _, out = render(sample_examples, style: :fs, color: true)
      expect(out).to include("\e[32m✔\e[0m \e[90madds two positive numbers\e[0m")
    end

    it "uses a cross and keeps the FAILED cross-reference for the failing leaf" do
      _, out = render(sample_examples, style: :fs)
      expect(out).to include("✗ adds a negative number (FAILED - 1)")
    end

    it "uses a dash and keeps the PENDING reason for the pending leaf" do
      _, out = render(sample_examples, style: :fs)
      expect(out).to include("- is skipped for now (PENDING: Temporarily skipped with xit)")
    end
  end

  context "in fv style" do
    it "uses Vitest's own glyphs for pass, fail, and pending" do
      _, out = render(sample_examples, style: :fv)
      expect(out).to include("✓ adds two positive numbers")
      expect(out).to include("× adds a negative number")
      expect(out).to include("↓ is skipped for now")
    end

    it "closes with a Vitest-shaped Test Files, Tests, and Duration footer" do
      _, out = render(sample_examples, style: :fv)
      expect(out).to include("Test Files  1 failed (1)")
      expect(out).to include("Tests  1 failed | 1 passed | 1 pending (3)")
      expect(out).to include("Duration  ")
    end

    it "shows per-leaf elapsed time in milliseconds" do
      _, out = render(sample_examples, style: :fv)
      expect(out).to include("✓ adds two positive numbers 1ms")
      expect(out).to include("× adds a negative number 2ms")
    end
  end
end
