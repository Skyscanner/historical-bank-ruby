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

require 'money/bank/historical'

redis_url = 'redis://localhost:6379'
namespace = 'currency_example'

Money::Bank::Historical.configure do |config|
  # (required) your OpenExchangeRates App ID
  config.oer_app_id = 'XXXXXXXXXXXXXXXXXXXXX'

  # (optional) currency relative to which all the rates are stored (default: EUR)
  config.base_currency = Money::Currency.new('USD')

  # (optional) the URL of the Redis server (default: 'redis://localhost:6379')
  config.redis_url = redis_url

  # (optional) Redis namespace to prefix all keys (default: 'currency')
  config.redis_namespace = namespace

  # (optional) set a timeout for the OER calls (default: 15 seconds)
  config.timeout = 20
end

bank = Money::Bank::Historical.instance

# In Rails, you can set this in the MoneyRails.configure block
Money.default_bank = bank

from_money = Money.new(100_00, 'EUR')
to_currency = 'GBP'

########## Exchange with the Bank object ##############

# exchange money normally as you do with normal banks (uses yesterday's closing rates)
bank.exchange_with(from_money, to_currency)

# exchange money with rates from December 10th 2016
bank.exchange_with_historical(from_money, to_currency, Date.new(2016, 12, 10))
# => #<Money fractional:8399 currency:GBP>

# can also pass a Time/DateTime object
bank.exchange_with_historical(from_money, to_currency, Time.utc(2016, 10, 2, 11, 0, 0))
# => #<Money fractional:8691 currency:GBP>

########## Exchange with the Money object ##############

# since it is set as the default bank, we can call Money#exchange_to (uses yesterday's closing rates)
from_money.exchange_to(to_currency)

# same result with a direct call on the Money object
from_money.exchange_to_historical(to_currency, Date.new(2016, 12, 10))
# => #<Money fractional:8399 currency:GBP>

########## Clean up Redis keys used here ##############

redis = Redis.new(url: redis_url)
keys = redis.keys("#{namespace}*")
redis.del(keys)
