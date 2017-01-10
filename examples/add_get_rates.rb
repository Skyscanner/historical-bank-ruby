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

from_money = Money.new(100_00, 'EUR')
to_currency = 'GBP'

############ Get single rate #################

# It accepts both ISO strings and Money::Currency objects.
bank.get_rate(Money::Currency.new('GBP'), 'CAD', Date.new(2016, 10, 1))
# => #<BigDecimal:7fd39fd2cb78,'0.1703941289 451827243E1',27(45)>

# Getting without a datetime will return yesterday's closing rate
bank.get_rate('CAD', 'CNY')

############ Add single rate #################

# It accepts both ISO strings and Money::Currency objects.
# Added rates should be relative to the base currency
date = Date.new(2016, 5, 18)

bank.add_rate('EUR', 'USD', 1.2, date)
bank.add_rate(Money::Currency.new('USD'), Money::Currency.new('GBP'), 0.8, date)

# 100 EUR = 100 * 1.2 USD = 100 * 1.2 * 0.8 GBP = 96 GBP
bank.exchange_with_historical(from_money, to_currency, date)
# => #<Money fractional:9600 currency:GBP>

# Adding without a datetime will set the rate to yesterday's closing rate
bank.add_rate('EUR', 'USD', 1.4)
bank.add_rate(Money::Currency.new('USD'), Money::Currency.new('GBP'), 0.6)

# 100 EUR = 100 * 1.4 USD = 100 * 1.4 * 0.6 GBP = 84 GBP
bank.exchange_with(from_money, to_currency)
# => #<Money fractional:8400 currency:GBP>

# trying to add a rate that is not relative to the base currency will fail
bank.add_rate('EUR', 'GBP', 0.96, date)
# ArgumentError: `from_currency` (EUR) or `to_currency` (GBP) should match the base currency USD

############ Add rates in bulk #################

# add historical exchange rates (relative to the base currency) in bulk
rates = {
  'EUR' => {
    '2015-09-10' => 0.11, # 1 USD = 0.11 EUR
    '2015-09-11' => 0.22,
    '2015-09-12' => 0.33
  },
  'GBP' => {
    '2015-09-10' => 0.44, # 1 USD = 0.44 GBP
    '2015-09-11' => 0.55,
    '2015-09-12' => 0.66
  },
  'VND' => {
    '2015-09-10' => 0.77, # 1 USD = 0.77 VND
    '2015-09-11' => 0.88,
    '2015-09-12' => 0.99
  }
}
bank.add_rates(rates)

# 100 EUR = 100 / 0.11 USD = 100 / 0.11 * 0.44 GBP = 400 GBP
bank.exchange_with_historical(from_money, to_currency, Date.new(2015, 9, 10))
# => #<Money fractional:40000 currency:GBP>

########## Clean up Redis keys used here #########

redis = Redis.new(url: redis_url)
keys = redis.keys("#{namespace}*")
redis.del(keys)
