# frozen_string_literal: true

require "json"
require "rutidy/version"

module Rutidy
  # A real RSpec formatter (registered the same way RSpec's own built-in
  # DocumentationFormatter is), not a post-processor of some other
  # formatter's text output. `example_group_started`/`example_group_finished`
  # fire as the runner actually descends/ascends the real describe/context
  # tree, so `@hierarchy` always reflects genuine nesting -- unlike stock
  # `rspec --format json`, whose `full_description` field is every group's
  # description concatenated with plain spaces and no separator, which
  # can't be split back into a tree without guessing. This formatter never
  # needs to guess: every example gets its own `hierarchy` array straight
  # from the stack RSpec itself maintains.
  #
  # Load with `rspec --require rutidy/formatter --format Rutidy::Formatter`,
  # or let `rutidy`'s own CLI wrap that invocation for you.
  class Formatter < RSpec::Core::Formatters::BaseFormatter
    RSpec::Core::Formatters.register self,
                                      :example_group_started, :example_group_finished,
                                      :example_passed, :example_failed, :example_pending,
                                      :dump_summary, :seed, :message, :close

    def initialize(output)
      super
      @hierarchy = []
      @output_hash = { version: Rutidy::VERSION }
    end

    def message(notification)
      (@output_hash[:messages] ||= []) << notification.message
    end

    def example_group_started(notification)
      @hierarchy << notification.group.description.strip
    end

    def example_group_finished(_notification)
      @hierarchy.pop
    end

    def example_passed(notification)
      record(notification.example)
    end

    def example_pending(notification)
      record(notification.example)
    end

    def example_failed(notification)
      record(notification.example, notification)
    end

    def dump_summary(summary)
      @output_hash[:summary] = {
        duration: summary.duration,
        example_count: summary.example_count,
        failure_count: summary.failure_count,
        pending_count: summary.pending_count,
      }
      @output_hash[:summary_line] = summary.totals_line
    end

    def seed(notification)
      return unless notification.seed_used?

      @output_hash[:seed] = notification.seed
    end

    def close(_notification)
      output.write JSON.generate(@output_hash)
    end

    private

    def record(example, failure_notification = nil)
      (@output_hash[:examples] ||= []) << format_example(example, failure_notification)
    end

    # Same field set stock `rspec --format json` gives you (description,
    # full_description, status, file_path, line_number, run_time,
    # pending_message, exception) plus the one field it's missing:
    # `hierarchy`, the real per-level nesting `render.rb` builds a tree from.
    def format_example(example, failure_notification)
      result = example.execution_result
      hash = {
        hierarchy: @hierarchy + [example.description.strip],
        description: example.description,
        full_description: example.full_description,
        status: result.status.to_s,
        file_path: example.metadata[:file_path],
        line_number: example.metadata[:line_number],
        run_time: result.run_time,
      }
      hash[:pending_message] = result.pending_message if result.pending_message
      hash[:exception] = format_exception(example.exception, failure_notification) if failure_notification
      hash
    end

    def format_exception(exception, failure_notification)
      {
        class: exception.class.name,
        message: exception.message,
        backtrace: failure_notification.formatted_backtrace,
      }
    end
  end
end
