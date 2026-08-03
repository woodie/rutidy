# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Kept out of the gemspec's own dev dependencies -- see rutidy.gemspec's
# comment. CI installs this group only on the one Ruby version that lints.
group :lint do
  gem "standard", "~> 1.3"
end
