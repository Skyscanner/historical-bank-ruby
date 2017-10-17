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

require 'money'
require 'money/rates_provider/open_exchange_rates'
require 'money/rates_store/historical_redis'

class Money
  module Bank
    # Bank that serves historical exchange rates. Inherits from
    # +Money::Bank::Base+
    class Historical < Bank::Base
      # Configuration class for +Money::Bank::Historical+
      class Configuration

        # +Money::Currency+ relative to which all exchange rates will be cached
        attr_accessor :base_currency
        # URL of the Redis server
        attr_accessor :redis_url
        # Redis namespace in which the exchange rates will be cached
        attr_accessor :redis_namespace
        # OpenExchangeRates app ID
        attr_accessor :oer_app_id
        # timeout to set in the OpenExchangeRates requests
        attr_accessor :timeout
        # type of account on OpenExchangeRates, to know which API endpoints are useable
        attr_accessor :oer_account_type

        def initialize
          @base_currency = Currency.new('EUR')
          @redis_url = 'redis://localhost:6379'
          @redis_namespace = 'currency'
          @oer_app_id = nil
          @timeout = 15
          @oer_account_type = RatesProvider::OpenExchangeRates::AccountType::ENTERPRISE
        end
      end

      # Returns the configuration (+Money::Bank::Historical::Configuration+)
      def self.configuration
        @configuration ||= Configuration.new
      end

      # Configures the bank. Parameters that can be configured:
      # - +oer_app_id+ - (required) your OpenExchangeRates App ID
      # - +oer_account_type+ - (optional) your OpenExchangeRates account type. Choose one of the values in the +Money::RatesProvider::OpenExchangeRates::AccountType+ module (default: +Money::RatesProvider::OpenExchangeRates::AccountType::ENTERPRISE+)
      # - +base_currency+ - (optional) +Money::Currency+ relative to which all the rates are stored (default: EUR)
      # - +redis_url+ - (optional) the URL of the Redis server (default: +redis://localhost:6379+)
      # - +redis_namespace+ - (optional) Redis namespace to prefix all keys (default: +currency+)
      # - +timeout+ - (optional) set a timeout for the OER calls (default: 15 seconds)
      #
      # ==== Examples
      #
      #   Money::Bank::Historical.configure do |config|
      #     config.oer_app_id = 'XXXXXXXXXXXXXXXXXXXXX'
      #     config.oer_account_type = Money::RatesProvider::OpenExchangeRates::AccountType::FREE
      #     config.base_currency = Money::Currency.new('USD')
      #     config.redis_url = 'redis://localhost:6379'
      #     config.redis_namespace = 'currency'
      #     config.timeout = 20
      #   end
      def self.configure
        yield(configuration)
        instance.setup
      end

      # Called at the end of the superclass' +initialize+ and also when
      # configuration changes. It initializes/resets all the instance variables.
      def setup
        @base_currency = Historical.configuration.base_currency
        # Hash[iso_currency][iso_date]
        @rates = {}
        @store = RatesStore::HistoricalRedis.new(@base_currency,
                                                 Historical.configuration.redis_url,
                                                 Historical.configuration.redis_namespace)
        @provider = RatesProvider::OpenExchangeRates.new(Historical.configuration.oer_app_id,
                                                         @base_currency,
                                                         Historical.configuration.timeout,
                                                         Historical.configuration.oer_account_type)
        # for controlling access to @rates
        @mutex = Mutex.new
      end

      # Adds historical rates in bulk to the Redis cache.
      #
      # ==== Parameters
      #
      # +currency_date_rate_hash+ - A +Hash+ of exchange rates, broken down by currency and date. See the example for details.
      #
      # ==== Examples
      #
      # Assuming USD is the base currency
      #
      #   rates = {
      #     'EUR' => {
      #       '2015-09-10' => 0.11, # 1 USD = 0.11 EUR
      #       '2015-09-11' => 0.22
      #     },
      #     'GBP' => {
      #       '2015-09-10' => 0.44, # 1 USD = 0.44 GBP
      #       '2015-09-11' => 0.55
      #     }
      #   }
      #   bank.add_rates(rates)

      def add_rates(currency_date_rate_hash)
        @store.add_rates(currency_date_rate_hash)
      end

      # Adds a single rate for a specific date to the Redis cache.
      # If no datetime is passed, it defaults to yesterday (UTC).
      # One of the passed currencies should match the base currency.
      #
      # ==== Parameters
      #
      # - +from_currency+ - Fixed currency of the +rate+ (https://en.wikipedia.org/wiki/Exchange_rate#Quotations). Accepts ISO String and +Money::Currency+ objects.
      # - +to_currency+ - Variable currency of the +rate+ (https://en.wikipedia.org/wiki/Exchange_rate#Quotations). Accepts ISO String and +Money::Currency+ objects.
      # - +rate+ - The price of 1 unit of +from_currency+ in +to_currency+.
      # - +datetime+ - The +Date+ this +rate+ was observed. If +Time+ is passed instead, it's converted to the UTC +Date+. If no +datetime+ is passed, it defaults to yesterday (UTC).
      #
      # ==== Errors
      #
      # - Raises +ArgumentError+ when neither +from_currency+, nor +to_currency+ match the +base_currency+ given in the configuration.
      #
      # ==== Examples
      #
      # Assuming USD is the base currency
      #
      #   from_money = Money.new(100_00, 'EUR')
      #   to_currency = 'GBP'
      #
      #   date = Date.new(2016, 5, 18)
      #
      #   # 1 EUR = 1.2 USD on May 18th 2016
      #   bank.add_rate('EUR', 'USD', 1.2, date)
      #   # 1 USD = 0.8 GBP on May 18th 2016
      #   bank.add_rate(Money::Currency.new('USD'), Money::Currency.new('GBP'), 0.8, date)
      #
      #   # 100 EUR = 100 * 1.2 USD = 100 * 1.2 * 0.8 GBP = 96 GBP
      #   bank.exchange_with_historical(from_money, to_currency, date)
      #   # => #<Money fractional:9600 currency:GBP>

      def add_rate(from_currency, to_currency, rate, datetime = yesterday_utc)
        from_currency = Currency.wrap(from_currency)
        to_currency = Currency.wrap(to_currency)

        if from_currency != @base_currency && to_currency != @base_currency
          raise ArgumentError, "`from_currency` (#{from_currency.iso_code}) or "\
                               "`to_currency` (#{to_currency.iso_code}) should "\
                               "match the base currency #{@base_currency.iso_code}"
        end

        date = datetime_to_date(datetime)

        currency_date_rate_hash = if from_currency == @base_currency
                                    {
                                      to_currency.iso_code => {
                                        date.iso8601 => rate
                                      }
                                    }
                                  else
                                    {
                                      from_currency.iso_code => {
                                        date.iso8601 => 1 / rate
                                      }
                                    }
                                  end

        add_rates(currency_date_rate_hash)
      end

      # Returns the +BigDecimal+ rate for converting +from_currency+
      # to +to_currency+ on a specific date. This is the price of 1 unit of
      # +from_currency+ in +to_currency+ on that date.
      # If rate is not found in the Redis cache, it is fetched from
      # OpenExchangeRates.
      # If no +datetime+ is passed, it defaults to yesterday (UTC).
      #
      # ==== Parameters
      #
      # - +from_currency+ - Fixed currency of the returned rate (https://en.wikipedia.org/wiki/Exchange_rate#Quotations). Accepts ISO String and +Money::Currency+ objects.
      # - +to_currency+ - Variable currency of the returned rate (https://en.wikipedia.org/wiki/Exchange_rate#Quotations). Accepts ISO String and +Money::Currency+ objects.
      # - +datetime+ - The +Date+ the returned rate was observed. If +Time+ is passed instead, it's converted to the UTC +Date+. If no +datetime+ is passed, it defaults to yesterday (UTC).
      #
      # ==== Examples
      #
      #   bank.get_rate(Money::Currency.new('GBP'), 'CAD', Date.new(2016, 10, 1))
      #   # => #<BigDecimal:7fd39fd2cb78,'0.1703941289 451827243E1',27(45)>

      def get_rate(from_currency, to_currency, datetime = yesterday_utc)
        from_currency = Currency.wrap(from_currency)
        to_currency = Currency.wrap(to_currency)

        date = datetime_to_date(datetime)

        rate_on_date(from_currency, to_currency, date)
      end

      # Exchanges +from_money+ to +to_currency+ using yesterday's
      # closing rates and returns a new +Money+ object.
      #
      # ==== Parameters
      #
      # - +from_money+ - The +Money+ object to exchange
      # - +to_currency+ - The currency to exchange +from_money+ to. Accepts ISO String and +Money::Currency+ objects.
      def exchange_with(from_money, to_currency)
        exchange_with_historical(from_money, to_currency, yesterday_utc)
      end

      # Exchanges +from_money+ to +to_currency+ using +datetime+'s
      # closing rates and returns a new +Money+ object.
      #
      # ==== Parameters
      #
      # - +from_money+ - The +Money+ object to exchange
      # - +to_currency+ - The currency to exchange +from_money+ to. Accepts ISO String and +Money::Currency+ objects.
      # - +datetime+ - The +Date+ to get the exchange rate from. If +Time+ is passed instead, it's converted to the UTC +Date+.
      def exchange_with_historical(from_money, to_currency, datetime)
        date = datetime_to_date(datetime)

        from_currency = from_money.currency
        to_currency = Currency.wrap(to_currency)

        rate = rate_on_date(from_currency, to_currency, date)
        to_amount = from_money.amount * rate

        Money.from_amount(to_amount, to_currency)
      end

      private

      def datetime_to_date(datetime)
        datetime.is_a?(Date) ? datetime : datetime.utc.to_date
      end

      # rate for converting 1 unit of from_currency (e.g. USD) to to_currency (e.g. GBP).
      # Comments below assume EUR is the base currency,
      # 1 EUR = 1.21 USD, and 1 EUR = 0.83 GBP on given date
      def rate_on_date(from_currency, to_currency, date)
        return 1 if from_currency == to_currency

        # 1 EUR = 1.21 USD => 1 USD = 1/1.21 EUR
        from_base_to_from_rate = base_rate_on_date(from_currency, date)
        # 1 EUR = 0.83 GBP
        from_base_to_to_rate   = base_rate_on_date(to_currency,   date)

        # 1 USD = 1/1.21 EUR = (1/1.21) * 0.83 GBP = 0.83/1.21 GBP
        from_base_to_to_rate / from_base_to_from_rate
      end

      # rate for converting 1 unit of base currency to currency
      def base_rate_on_date(currency, date)
        return 1 if @base_currency == currency

        rate = get_base_rate(currency, date) ||
               fetch_stored_base_rate(currency, date) ||
               fetch_provider_base_rate(currency, date)

        if rate.nil?
          raise UnknownRate, "Rate from #{currency} to #{@base_currency} "\
                             "on #{date} not found"
        end

        rate
      end

      def fetch_stored_base_rate(currency, date)
        date_rate_hash = @store.get_rates(currency)

        if date_rate_hash && !date_rate_hash.empty?
          rate = date_rate_hash[date.iso8601]
          set_base_rates(currency, date_rate_hash)

          rate
        end
      end

      def fetch_provider_base_rate(currency, date)
        currency_date_rate_hash = @provider.fetch_rates(date)

        date_rate_hash = currency_date_rate_hash[currency.iso_code]
        rate = date_rate_hash && date_rate_hash[date.iso8601]

        if currency_date_rate_hash && !currency_date_rate_hash.empty?
          @store.add_rates(currency_date_rate_hash)
        end

        if date_rate_hash && !date_rate_hash.empty?
          set_base_rates(currency, date_rate_hash)
        end

        rate
      end

      def set_base_rates(currency, date_rate_hash)
        iso_currency = currency.iso_code
        @mutex.synchronize do
          @rates[iso_currency] = {} if @rates[iso_currency].nil?
          @rates[iso_currency].merge!(date_rate_hash)
        end
      end

      def get_base_rate(currency, date)
        @mutex.synchronize do
          rates = @rates[currency.iso_code]
          rates[date] if rates
        end
      end

      # yesterday in UTC timezone
      def yesterday_utc
        Time.now.utc.to_date - 1
      end
    end
  end

  # Exchanges to +other_currency+ using +datetime+'s
  # closing rates and returns a new +Money+ object.
  # +rounding_method+ is ignored in this version of the gem.
  #
  # ==== Parameters
  #
  # - +other_currency+ - The currency to exchange to. Accepts ISO String and +Money::Currency+ objects.
  # - +datetime+ - The +Date+ to get the exchange rate from. If +Time+ is passed instead, it's converted to the UTC +Date+.
  # - +rounding_method+ - This parameter is ignored in this version of the gem.

  def exchange_to_historical(other_currency, datetime, &rounding_method)
    Bank::Historical.instance.exchange_with_historical(self, other_currency,
                                                       datetime, &rounding_method)
  end
end
