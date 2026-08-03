.PHONY: build install test lint check

build:
	gem build rutidy.gemspec

install: build
	bundle exec rake install

# Dogfoods rutidy on its own suite -- the Ruby equivalent of gorderly's
# `go test -v ./... | gorderly -fd` / xctidy's `swift test | xctidy Tests`.
test:
	mkdir -p tmp
	bundle exec rspec --require rutidy/formatter --format Rutidy::Formatter --out tmp/rutidy-report.json
	bundle exec exe/rutidy -fd tmp/rutidy-report.json

lint:
	bundle exec standardrb

# Terser than `test` on purpose: silent on success, full log on any failure.
check:
	@LOG=$$(mktemp); \
	if bundle exec standardrb >> "$$LOG" 2>&1 && bundle exec rspec >> "$$LOG" 2>&1; then \
		echo "PASS"; \
	else \
		cat "$$LOG"; \
		exit 1; \
	fi
