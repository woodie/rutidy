# Picking up rutidy in a new Cowork session

Cross-project conventions (git locks, sandbox toolchain gaps, pushing, comments, code
style) are in `~/workspace/woodie/docs/COWORK.md`.

## What this is

RSpec sibling to `gorderly`/`xctidy`/`kotidy`: same `classic`/`fd`/`fs`/`fv` output
styles, `Render.call` mirroring `gorderly`'s `render.go` almost line for line. Two
pieces:

- `lib/rutidy/formatter.rb` -- a real RSpec formatter (`Rutidy::Formatter`,
  registered the same way RSpec's own `DocumentationFormatter` is), producing a
  structured JSON report.
- `lib/rutidy/render.rb` + `lib/rutidy/cli.rb` -- reads that JSON (or wraps `rspec`
  directly, matching `gomeleon`'s own "wrap the CLI or read its report" duality) and
  renders the four styles.

## Why a real formatter, not a text post-processor

Stock `rspec --format json` (`RSpec::Core::Formatters::JsonFormatter`, read from its
real source before building this) only gives each example a flattened
`full_description` string -- every `describe`/`context`/`it` concatenated with plain
spaces, no separator. Reconstructing a tree from that would be strictly worse than
the comma-disambiguation problem `xctidy` solves for Quick/Nimble, since RSpec
doesn't even delimit with commas. `example.id`'s bracket notation
(`./spec/foo_spec.rb[1:2:1]`) does encode real positional nesting, but that's *no*
help recovering each level's *text* -- only its depth/position.

RSpec's own `DocumentationFormatter` doesn't have this problem: it renders correctly
in real time because `example_group_started`/`example_group_finished` notifications
fire as the runner actually descends/ascends the tree, each carrying
`notification.group.description` directly. `Rutidy::Formatter` hooks the same
notifications and accumulates a `@hierarchy` stack -- every example's `hierarchy`
array in the JSON output comes from the real stack RSpec itself maintains, never
text-diffing or guessing.

## Testing

`spec/rutidy/formatter_spec.rb` drives a real, isolated RSpec suite through
`Rutidy::Formatter` via `RSpec::Core::Sandbox` (`require "rspec/core/sandbox"`) --
the same mechanism rspec-core's own spec suite uses to test its built-in formatters
(confirmed by reading `spec/support/formatter_support.rb` upstream, not guessed).
`group.run(reporter)` on a real `RSpec.describe(...)`-built group fires every
notification for real; no example/group needs mocking. `spec/rutidy/render_spec.rb`
tests `Render` directly against hand-built example hashes, no RSpec sandboxing
needed there since it's pure data in, text out.

## Sandbox limitation

No network route to RubyGems from the Cowork sandbox (`gem install` fails `403
Forbidden`, same as `humane-ruby`) -- and unlike `humane-ruby`, this sandbox doesn't
even have `rspec` installed yet to smoke-test against directly. Everything here is
written by inspection against RSpec's real source (`json_formatter.rb`,
`documentation_formatter.rb`, `example_group.rb`, `sandbox.rb`, and
`formatter_support.rb`, all fetched and read, not recalled from memory) -- needs a
real `bundle install && make check` on the user's own Mac before trusting any of it.

## A real bug the first `bundle install && make check` caught

`formatter.rb` originally subclassed `RSpec::Core::Formatters::BaseFormatter`
without requiring it first, on the wrong assumption that loading `rspec/core`
(implicit in running under `rspec` at all) would already have it defined --
`NameError: uninitialized constant RSpec::Core::Formatters::BaseFormatter` on the
very first real `make test`. Fixed by requiring `rspec/core/formatters` and
`rspec/core/formatters/base_formatter` explicitly at the top of the file, matching
what stock `json_formatter.rb` does (`RSpec::Support.require_rspec_core
"formatters/base_formatter"` -- not used verbatim here since that helper's relative-
path resolution is meant for code living inside the rspec-core gem itself, not a
third-party one). `render.rb`/`cli.rb` have no such dependency and were verified
directly in the sandbox (`ruby -Ilib`, all four styles, piped stdin, an existing
report file, `--version`) since they don't need RSpec loaded at all -- only
`formatter.rb` needed a real `rspec` process to catch this.

Also fixed the same round: ~30 `standardrb` violations (trailing commas in hash/
array literals, spaces inside `{}`, multi-line argument/array alignment, missing
ternary parens) -- style-only, no behavior change.

## Current status

Fixes made by inspection (still no `rspec` gem in this sandbox -- see "Sandbox
limitation" above); `render.rb`/`cli.rb` re-verified via `ruby -Ilib` after the lint
pass, output unchanged. `formatter.rb`'s actual fix is unverified here. Needs, on
your Mac:

```
cd ~/workspace/rutidy
bundle install
make check
make test
```
