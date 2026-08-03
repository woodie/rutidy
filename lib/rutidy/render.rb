# frozen_string_literal: true

module Rutidy
  # Walks the leaves `Formatter` (or a real `rspec --format json` report
  # extended with a `hierarchy` array) produced and renders them as a nested
  # RSpec `-fd`-style tree, the same dedupe-shared-prefix walk `gorderly`'s
  # `render.go` and `xctidy`'s `Engine.swift` use, just over each example's
  # real `hierarchy` array instead of a `/`-split or comma-disambiguated
  # string. Four styles (`:classic`/`:fd`/`:fs`/`:fv`) share one closing
  # footer, except `:fv`, which closes with Vitest's own `Test Files`/
  # `Tests`/`Duration` shape.
  #
  # Unlike `gorderly`, there's no fake "package path" label above the tree --
  # RSpec has no equivalent concept, so the first top-level `describe` is
  # just the first real node. A blank line still goes before every
  # top-level group, including the first -- that's not a `gorderly`-style
  # workaround here, it's genuine RSpec `-fd` behavior (its own
  # `DocumentationFormatter#example_group_started` does `output.puts if
  # @group_level == 0` unconditionally).
  module Render
    ANSI_PREFIX = "\e["
    COLORS = {
      red: "31",
      green: "32",
      bright_green: "92",
      yellow: "33",
      cyan: "36",
      gray: "90",
    }.freeze

    FailureEntry = Struct.new(:n, :full, :output)

    module_function

    # @return [Integer] the number of failed examples (0 means a clean run)
    def call(examples, style:, out:, color: true)
      colorize = ->(name, text) { color ? "#{ANSI_PREFIX}#{COLORS.fetch(name)}m#{text}#{ANSI_PREFIX}0m" : text }

      total = 0
      pending = 0
      failed_count = 0
      total_elapsed = 0.0
      failures = []
      files_total = {}
      files_failed = {}
      prev_path = []

      examples.each do |example|
        hierarchy = example.fetch(:hierarchy)
        path = hierarchy[0..-2]
        leaf_name = hierarchy.last

        shared = 0
        shared += 1 while shared < prev_path.length && shared < path.length && prev_path[shared] == path[shared]

        out.puts if shared.zero?
        (shared...path.length).each { |i| out.puts("#{"  " * i}#{path[i]}") }

        total += 1
        total_elapsed += example[:run_time]
        indent = "  " * path.length
        file = example[:file_path]
        files_total[file] = true if file

        case example[:status]
        when "failed"
          failed_count += 1
          files_failed[file] = true if file
          n = failures.length + 1
          failures << FailureEntry.new(n, hierarchy, format_backtrace(example))
          out.puts("#{indent}#{colorize_fail(style, leaf_name, example, n, colorize)}")
        when "pending"
          pending += 1
          out.puts("#{indent}#{colorize_pending(style, leaf_name, example, colorize)}")
        else
          out.puts("#{indent}#{colorize_pass(style, leaf_name, example, colorize)}")
        end

        prev_path = path
      end
      out.puts

      if failures.any?
        out.puts("Failures:")
        failures.each do |f|
          out.puts
          out.puts("  #{f.n}) #{f.full.join(" ")}")
          f.output.each { |line| out.puts("     #{line}") }
        end
        out.puts
      end

      if style == :fv
        write_vitest_footer(out, colorize, total: total, failed_count: failed_count, pending: pending,
                                            total_elapsed: total_elapsed, files_total: files_total.size,
                                            files_failed: files_failed.size)
      else
        write_shared_footer(out, colorize, total: total, failed_count: failed_count, pending: pending,
                                            total_elapsed: total_elapsed)
      end

      failed_count
    end

    def write_shared_footer(out, colorize, total:, failed_count:, pending:, total_elapsed:)
      verdict = failed_count.positive? ? "Test Failed" : "Test Succeeded"
      verdict_color = failed_count.positive? ? :red : :green
      out.puts(colorize.call(verdict_color, verdict))
      out.puts(colorize.call(verdict_color,
                              format("Tests Passed: %d failed, %d pending, %d total (%s seconds)",
                                     failed_count, pending, total, format_seconds(total_elapsed))))
    end

    def write_vitest_footer(out, colorize, total:, failed_count:, pending:, total_elapsed:, files_total:, files_failed:)
      passed = total - failed_count - pending
      files_passed = files_total - files_failed
      out.puts(vitest_summary_line("Test Files", colorize, failed: files_failed, passed: files_passed, pending: 0, total: files_total))
      out.puts(vitest_summary_line("Tests", colorize, failed: failed_count, passed: passed, pending: pending, total: total))
      out.puts(format("%11s  %s", "Duration", format_vitest_duration(total_elapsed)))
    end

    def vitest_summary_line(label, colorize, failed:, passed:, pending:, total:)
      parts = []
      parts << colorize.call(:red, "#{failed} failed") if failed.positive?
      parts << colorize.call(:green, "#{passed} passed") if passed.positive?
      parts << colorize.call(:gray, "#{pending} pending") if pending.positive?
      parts << "0 passed" if parts.empty?
      format("%11s  %s (%d)", label, parts.join(" | "), total)
    end

    def colorize_pass(style, name, example, colorize)
      case style
      when :classic
        "#{colorize.call(:green, "✔")} #{name} (#{colorize.call(:green, format_seconds(example[:run_time]))} seconds)"
      when :fs
        "#{colorize.call(:green, "✔")} #{colorize.call(:gray, name)}"
      when :fv
        number, unit = format_vitest_duration_parts(example[:run_time])
        "#{colorize.call(:green, "✓")} #{name} #{colorize.call(:green, number)}#{colorize.call(:bright_green, unit)}"
      else # :fd
        colorize.call(:green, name)
      end
    end

    def colorize_fail(style, name, example, n, colorize)
      case style
      when :classic
        "#{colorize.call(:red, "✖")} #{name} (FAILED - #{n}) (#{colorize.call(:red, format_seconds(example[:run_time]))} seconds)"
      when :fs
        colorize.call(:red, "✗ #{name} (FAILED - #{n})")
      when :fv
        colorize.call(:red, "× #{name} #{format_vitest_duration(example[:run_time])}")
      else # :fd
        colorize.call(:red, "#{name} (FAILED - #{n})")
      end
    end

    # RSpec's own vocabulary is "pending" -- not "skipped" the way Go/Ginkgo
    # call it -- so every style says PENDING, matching what `rspec`'s real
    # `-fd`/`--format documentation` would say for the same example. Include
    # the pending reason where RSpec itself would (`-fd`/`-fs`); `:classic`
    # and `:fv` stay terse (glyph/name/time only), matching how `gorderly`'s
    # classic and Vitest's own tree both treat a skip.
    def colorize_pending(style, name, example, colorize)
      case style
      when :classic
        "#{colorize.call(:cyan, "⊘")} #{name} (#{colorize.call(:cyan, format_seconds(example[:run_time]))} seconds)"
      when :fs
        colorize.call(:cyan, "- #{name} #{pending_suffix(example)}")
      when :fv
        colorize.call(:gray, "↓ #{name}")
      else # :fd
        colorize.call(:yellow, "#{name} #{pending_suffix(example)}")
      end
    end

    def pending_suffix(example)
      reason = example[:pending_message]
      reason ? "(PENDING: #{reason})" : "(PENDING)"
    end

    def format_backtrace(example)
      exception = example[:exception]
      return [] unless exception

      ["#{exception[:class]}: #{exception[:message]}"] + Array(exception[:backtrace])
    end

    def format_seconds(seconds)
      seconds < 1 ? format("%.4f", seconds) : format("%.2f", seconds)
    end

    def format_vitest_duration_parts(seconds)
      ms = seconds * 1000
      return [format("%.2f", ms / 1000), "s"] if ms > 1000

      [ms.round.to_s, "ms"]
    end

    def format_vitest_duration(seconds)
      number, unit = format_vitest_duration_parts(seconds)
      "#{number}#{unit}"
    end
  end
end
