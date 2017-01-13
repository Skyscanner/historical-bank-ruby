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
require 'httparty'

class Money
  module RatesProvider
    # Raised when a +RatesProvider+ request fails
    class RequestFailed < StandardError; end

    # Retrieves exchange rates from OpenExchangeRates.org API, relative
    # to the given +base_currency+.
    # It is fetching rates for all currencies in one request, as we are charged on a
    # "per date" basis. I.e. one month's data for all currencies counts as 30 calls.
    class OpenExchangeRates
      include HTTParty
      base_uri 'https://openexchangerates.org/api'

      # minimum date that OER has data
      # (https://docs.openexchangerates.org/docs/historical-json)
      MIN_DATE = Date.new(1999, 1, 1).freeze

      # ==== Parameters
      # - +oer_app_id+ - App ID for the OpenExchangeRates API access (Enterprise or Unlimited plan)
      # - +base_currency+ - The base currency that will be used for the OER requests. It should be a +Money::Currency+ object.
      # - +timeout+ - The timeout in seconds to set on the requests
      def initialize(oer_app_id, base_currency, timeout)
        @oer_app_id = oer_app_id
        @base_currency_code = base_currency.iso_code
        @timeout = timeout
      end

      # Fetches the rates for all available quote currencies for a whole month.
      # Fetching for all currencies or just one has the same API charge.
      # In addition, the API doesn't allow fetching more than a month's data.
      #
      # It returns a +Hash+ with the rates for each quote currency and date
      # as shown in the example. Rates are +BigDecimal+.
      #
      # ==== Parameters
      #
      # - +date+ - +date+'s month is the month for which we request rates. Minimum +date+ is January 1st 1999, as defined by the OER API (https://docs.openexchangerates.org/docs/api-introduction). Maximum +date+ is yesterday (UTC), as today's rates are not final (https://openexchangerates.org/faq/#timezone).
      #
      # ==== Errors
      #
      # - Raises +ArgumentError+ when +date+ is less than January 1st 1999, or greater than yesterday (UTC)
      # - Raises +Money::RatesProvider::RequestFailed+ when the OER request fails
      #
      # ==== Examples
      #
      #   oer.fetch_month_rates(Date.new(2016, 10, 5))
      #   # => {"AED"=>{"2016-10-01"=>#<BigDecimal:7fa19a188e98,'0.3672682E1',18(36)>, "2016-10-02"=>#<BigDecimal:7fa19b11a5c8,'0.367296E1',18(36)>, ...
      def fetch_month_rates(date)
        if date < MIN_DATE || date > max_date
          raise ArgumentError, "Provided date #{date} for OER query should be "\
                               "between #{MIN_DATE} and #{max_date}"
        end

        end_of_month = Date.civil(date.year, date.month, -1)

        start_date = Date.civil(date.year, date.month, 1)
        end_date = [end_of_month, max_date].min

        options = request_options(start_date, end_date)
        response = self.class.get('/time-series.json', options)

        unless response.success?
          raise RequestFailed, "Month rates request failed for #{date} - "\
                               "Code: #{response.code} - Body: #{response.body}"
        end

        result = Hash.new { |hash, key| hash[key] = {} }

        # sample response can be found in spec/fixtures.
        # we're transforming the response from Hash[iso_date][iso_currency] to
        # Hash[iso_currency][iso_date], as it will allow more efficient caching/retrieving
        response['rates'].each do |iso_date, day_rates|
          day_rates.each do |iso_currency, rate|
            result[iso_currency][iso_date] = rate.to_d
          end
        end

        result
      end

      private

      def request_options(start_date, end_date)
        {
          query: {
            app_id:  @oer_app_id,
            start:   start_date,
            end:     end_date,
            base:    @base_currency_code
          },
          timeout: @timeout
        }
      end

      # A historical day's rates can be obtained when the date changes at 00:00 UTC
      # https://openexchangerates.org/faq/#timezone
      def max_date
        Time.now.utc.to_date - 1
      end
    end
  end
end
