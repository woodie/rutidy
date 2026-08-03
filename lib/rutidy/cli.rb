# frozen_string_literal: true

require "json"
require "tempfile"
require "rutidy/version"
require "rutidy/render"

module Rutidy
  # `rutidy`'s two modes, matching `gomeleon`'s own "wrap the CLI, or read
  # its JSON report directly" duality:
  #
  #   rutidy                  # wraps `rspec` with no args
  #   rutidy spec/foo_spec.rb # wraps `rspec spec/foo_spec.rb`
  #   rutidy -fd spec/        # style flag + wrapped invocation
  #   rutidy report.json      # formats an existing report file directly
  #   rspec ... | rutidy -fs  # reads a piped report from stdin
  #
  # A single argument ending in `.json` is treated as an existing report to
  # render; anything else on the command line is handed straight through to
  # `rspec` (with `Formatter` inserted via `--require`/`--format`). Piped
  # stdin with no arguments at all is read as a report too, the same way
  # `gorderly`'s `openInput` treats piped stdin vs. shelling out to `go test`
  # itself.
  class CLI
    STYLE_ALIASES = {
      "documentation" => :fd,
      "spec" => :fs,
      "vitest" => :fv,
    }.freeze

    def self.run(argv, out: $stdout, err: $stderr, stdin: $stdin)
      new(argv, out: out, err: err, stdin: stdin).run
    end

    def initialize(argv, out:, err:, stdin:)
      @argv = argv.dup
      @out = out
      @err = err
      @stdin = stdin
      @style = :classic
      @color = @out.respond_to?(:tty?) && @out.tty? && ENV["NO_COLOR"].nil?
    end

    def run
      if wants_version?
        @out.puts("rutidy #{Rutidy::VERSION}")
        return 0
      end

      rest = parse_flags!
      examples = load_examples(rest)
      return 1 if examples.nil?

      Render.call(examples, style: @style, out: @out, color: @color).positive? ? 1 : 0
    end

    private

    def wants_version?
      @argv.include?("--version") || @argv.include?("-v")
    end

    def parse_flags!
      rest = []
      @argv.each do |arg|
        case arg
        when "-fd" then @style = :fd
        when "-fs" then @style = :fs
        when "-fv" then @style = :fv
        when /\A--format[= ](\w+)\z/
          @style = STYLE_ALIASES.fetch(Regexp.last_match(1)) do
            @err.puts("rutidy: unknown --format #{Regexp.last_match(1)}")
            @style
          end
        else rest << arg
        end
      end
      rest
    end

    def load_examples(rest)
      if rest.length == 1 && rest.first.end_with?(".json")
        return parse_report(File.read(rest.first))
      end

      if rest.empty? && !@stdin.tty?
        return parse_report(@stdin.read)
      end

      run_rspec(rest)
    end

    def parse_report(json_text)
      JSON.parse(json_text, symbolize_names: true).fetch(:examples, [])
    rescue JSON::ParserError => e
      @err.puts("rutidy: couldn't parse report: #{e.message}")
      nil
    end

    def run_rspec(args)
      Tempfile.create(["rutidy", ".json"]) do |tmp|
        cmd = ["rspec", "--require", "rutidy/formatter", "--format", "Rutidy::Formatter",
               "--out", tmp.path, *args]
        # `rspec` exits non-zero whenever any example fails -- that's the
        # normal case this tool exists to render, not an error. Only the
        # report ending up empty (rspec never got far enough to write one --
        # a load error, an unrecognized flag, no matching spec files) is a
        # real problem worth surfacing here.
        system(*cmd, out: @err, err: @err)

        content = File.read(tmp.path)
        if content.strip.empty?
          @err.puts("rutidy: `#{cmd.join(" ")}` produced no report -- see rspec's own output above")
          return nil
        end

        parse_report(content)
      end
    end
  end
end
