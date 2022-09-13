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
require 'redis'

class Money
  module RatesStore
    # Raised when a +RatesStore+ request fails
    class RequestFailed < StandardError; end

    # Exchange rates cache implemented with Redis.
    #
    # All cached rates are relative to the given +base_currency+.
    # It stores +Hash+ es with keys formatted as +namespace:base_currency:quote_currency+ .
    # These hashes contain ISO dates as keys with base currency rates as values.
    #
    # ==== Examples
    #
    # If +currency+ is the Redis namespace we used in the constructor,
    # USD is the base currency, and we're looking for HUF rates, they can be found
    # in the +currency:USD:HUF+ key, and their format will be
    #   {
    #     "2016-05-01": "0.272511002E3", # Rates are stored as BigDecimal Strings
    #     "2016-05-02": "0.270337998E3",
    #     "2016-05-03": "0.271477498E3"
    #   }
    class HistoricalRedis
      # ==== Parameters
      #
      # - +base_currency+ - The base currency relative to which all rates are stored
      # - +redis_url+ - The URL of the Redis server
      # - +namespace+ - Namespace with which to prefix all Redis keys

      def initialize(base_currency, redis_url, namespace)
        @base_currency = base_currency
        @redis = Redis.new(url: redis_url)
        @namespace = namespace
      end

      # Adds historical rates in bulk
      #
      # ==== Parameters
      #
      # +currency_date_rate_hash+ - A +Hash+ of exchange rates, broken down by currency and date. See the example for details.
      #
      # ==== Errors
      #
      # - Raises +ArgumentError+ when the base currency is included in +currency_date_rate_hash+ with rate other than 1.
      # - Raises +Money::RatesStore::RequestFailed+ when the Redis request fails
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
      #   store.add_rates(rates)

      def add_rates(currency_date_rate_hash)
        if !currency_date_rate_hash[@base_currency.iso_code].nil? &&
           !currency_date_rate_hash[@base_currency.iso_code].values.all? { |r| r == 1 }

          raise ArgumentError, "When base currency #{@base_currency.iso_code} is included "\
                               "in given Hash #{currency_date_rate_hash}, its rate should  "\
                               'be equal to 1'
        end

        @redis.pipelined do |pipeline|
          currency_date_rate_hash.each do |iso_currency, iso_date_rate_hash|
            k = key(iso_currency)
            pipeline.mapped_hmset(k, iso_date_rate_hash)
          end
        end
      rescue Redis::BaseError => e
        raise RequestFailed, "Error while storing rates - #{e.message} - "\
                             "rates: #{currency_date_rate_hash}"
      end

      # Returns a +Hash+ of rates for all cached dates for the given currency.
      #
      # ==== Parameters
      #
      # - +currency+ - The quote currency for which we request all the cached rates. This is a +Money::Currency+ object.
      #
      # ==== Examples
      #
      #   store.get_rates(Money::Currency.new('GBP'))
      #   # => {"2017-01-01"=>#<BigDecimal:7fa19ba27260,'0.809782E0',9(18)>, "2017-01-02"=>#<BigDecimal:7fa19ba27210,'0.814263E0',9(18)>, "2017-01-03"=>#<BigDecimal:7fa19ba271c0,'0.816721E0',9(18)>, ...
      def get_rates(currency)
        k = key(currency.iso_code)
        iso_date_rate_hash = @redis.hgetall(k)

        iso_date_rate_hash.each do |iso_date, rate_string|
          iso_date_rate_hash[iso_date] = rate_string.to_d
        end
      rescue Redis::BaseError => e
        raise RequestFailed, 'Error while retrieving rates for '\
                                "#{currency} - #{e.message}"\
      end

      private

      # e.g. currency:EUR:USD
      def key(currency_iso)
        [@namespace, @base_currency.iso_code, currency_iso].join(':')
      end
    end
  end
end
