#
# Copyright 2017 Skyscanner Limited.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'historical-bank'
  s.version     = '0.1.3'
  s.summary     = 'Historical Bank'
  s.description = 'A `Money::Bank::Base` with historical exchange rates'
  s.authors     = ['Kostis Dadamis', 'Emili Parreno']
  s.email       = ['kostis.dadamis@skyscanner.net']
  s.homepage    = 'https://github.com/Skyscanner/historical-bank-ruby'
  s.license     = 'Apache-2.0'

  require 'rake'
  s.files = FileList['lib/**/*.rb', 'Gemfile', 'examples/*.rb',
                     'historical-bank.gemspec', 'spec/**/*.rb'].to_a
  s.files += ['README.md', 'LICENSE', 'CONTRIBUTING.md', 'AUTHORS',
              'CHANGELOG.md', 'spec/fixtures/time-series-2015-09.json']

  s.test_files = s.files.grep(%r{^spec/})

  s.extra_rdoc_files = ['README.md']

  s.requirements = 'redis'

  s.require_path = 'lib'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'money',    '~> 6.7'
  s.add_runtime_dependency 'httparty', '~> 0.14'
  s.add_runtime_dependency 'redis',    ['>=3.3', '< 4.1']

  s.add_development_dependency 'rspec',      '~> 3.5'
  s.add_development_dependency 'pry-byebug', '~> 3.4'
  s.add_development_dependency 'rubocop',    '~> 0.52'
  s.add_development_dependency 'rack-test',  '~> 0.6'
  s.add_development_dependency 'webmock',    '~> 2.3'
  s.add_development_dependency 'faker',      '~> 1.6'
  s.add_development_dependency 'timecop',    '~> 0.8'
end
