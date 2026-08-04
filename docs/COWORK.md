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

## CI: the Ruby 3.0 matrix leg needed lint split into its own job

Two real, separate CI failures, both only visible from an actual GitHub Actions run
(not reproducible from this sandbox, which has no `rspec`/`bundle` executables at
all -- see "Sandbox limitation" above):

1. **`ruby/setup-ruby`'s "Installing Bundler" step failed outright on the `3.0`
   leg.** By default it installs whatever `BUNDLED WITH` says in the committed
   `Gemfile.lock` -- `2.6.9` here, from whatever Bundler happened to be on the
   machine that ran `bundle install` locally -- regardless of which Ruby version
   the matrix leg is actually running. Bundler `2.6.9` itself requires Ruby
   `>= 3.1`, so installing it under Ruby `3.0.7` failed before `bundle install`
   ever ran. Fixed with `bundler: default` on the `setup-ruby` step, which installs
   whichever Bundler each Ruby version actually ships with instead.
2. **`bundle install` itself then failed on the `3.0` leg**: `parallel-2.1.0`
   (a `rubocop`/`standard` transitive dependency) requires Ruby `>= 3.3`, and
   `bundler-cache: true` runs in deployment mode (frozen lockfile), so it can't
   silently resolve an older `parallel` for the older Ruby leg -- it just fails.
   `standard` is dev/lint-only tooling that never ships to users, so there's no
   real reason it needs to satisfy the same Ruby floor `rutidy`'s own runtime code
   does. Moved `standard` out of `rutidy.gemspec`'s `add_development_dependency`
   and into the `Gemfile`'s own `group :lint`; CI's `test` job sets
   `BUNDLE_WITHOUT: lint` so no matrix leg ever needs to resolve it, and a
   separate single-Ruby `lint` job (pinned to `3.3`, the version actually running
   `standardrb`) installs and runs it instead.

**`Gemfile.lock` needs a real `bundle install` on your Mac after this** to pick up
the `Gemfile`/`gemspec` group change -- commit the regenerated lockfile alongside,
same as any dependency-shape change (see
`~/workspace/woodie/docs/COWORK.md`'s "Shared libraries across sibling repos" for
why that commit can't be skipped or deferred).

## `-fv`'s unit-suffix color is `#b9e4b4`, not ANSI-16 bright green

A real `vitest run` color-picker readout showed the actual shade; the old
`:bright_green` (`92`, closer to `#2ee721`) was a guess. Now a 24-bit
true-color `:vitest_unit` (`38;2;185;228;180`) since no ANSI-16 entry is
close -- see `gorderly`'s `docs/COWORK.md` for the full note, ported
identically here.

**Tagged `v0.1.1` and published to RubyGems in the same session** -- also
the session that surfaced a real gotcha now documented in
`~/workspace/woodie/docs/COWORK.md`'s "Tagging releases" section: the first
`v0.1.1` tag was created before `lib/rutidy/version.rb` got bumped off
`0.1.0`, so `gem build` kept producing `rutidy-0.1.0.gem` even after the tag
said `v0.1.1`. Caught when `gem push rutidy-0.1.1.gem` failed with "no such
file" -- fixed by bumping the version file as its own commit, then deleting
and recreating the tag on that commit before re-pushing and re-building.

## Current status

Confirmed for real on the user's own Mac: `make check` (`standardrb` + full spec
suite, 25 examples) is clean, and `make test` -- the real end-to-end path, `rspec`
running with `Rutidy::Formatter` piped into `rutidy`'s own CLI (`-fs` style, the
Makefile's own choice) -- dogfoods the whole pipeline correctly, real nested tree,
real shared footer
(`Tests Passed: 0 failed, 0 pending, 25 total`). CI is green on GitHub Actions
(`test` matrix across Ruby 3.0/3.3, separate `lint` job), including the real
`3.0`-leg failures above -- both confirmed fixed against actual CI logs, not just
reasoned about.

**Tagged `v0.1.0` and published to RubyGems.org as `rutidy` `0.1.0`** -- woodie's
first gem push on this account since `humane-ruby`. `gem build`/`gem push` both
confirmed clean (`Successfully registered gem: rutidy (0.1.0)`), package contents
verified via a real `gem build` + unpack in this sandbox beforehand (see the
gemspec-allowlist entry above) -- only `LICENSE`, `README.md`, `exe/rutidy`, and
`lib/**/*.rb` ship, `docs/COWORK.md`/`docs/example.png` correctly excluded.
GitHub release notes attached from `docs/releases/v0.1.0.md` (`gh release create
v0.1.0 --notes-file docs/releases/v0.1.0.md`), not left as the bare tag message.

**Adopted outside its own repo:** `humane-ruby`'s `make test` now runs `bundle
exec rutidy -fs spec` instead of `rspec -fd spec` -- the first real consumer,
confirming the wrap-`rspec`-directly CLI path (not just the formatter-plus-JSON
path this repo's own `make test` exercises) against a second, independent spec
suite. Completes the four-language family on equal footing: `kotidy`/`gorderly`/
`xctidy`/`rutidy` all render the same `classic`/`fd`/`fs`/`fv` styles now, one per
language in `~/workspace/netpress`'s `docs/COWORK.md`-adjacent `talks/` posts and
`public/periodic.js` (`Rt`, replacing the unrelated `gomeleon`/`Gm` entry there --
`gomeleon` itself is untouched, just no longer listed alongside this family).
