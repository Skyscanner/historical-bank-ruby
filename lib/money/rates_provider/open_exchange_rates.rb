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

      module AccountType
        FREE = 'Free'.freeze
        DEVELOPER = 'Developer'.freeze
        ENTERPRISE = 'Enterprise'.freeze
        UNLIMITED = 'Unlimited'.freeze
      end

      # ==== Parameters
      # - +oer_app_id+ - App ID for the OpenExchangeRates API access
      # - +base_currency+ - The base currency that will be used for the OER requests. It should be a +Money::Currency+ object.
      # - +timeout+ - The timeout in seconds to set on the requests
      # - +oer_account_type+ - The OpenExchangeRates account type. Should be one of +AccountType::FREE+, +DEVELOPER+, +ENTERPRISE+, or +UNLIMITED+
      def initialize(oer_app_id, base_currency, timeout, oer_account_type)
        @oer_app_id = oer_app_id
        @base_currency_code = base_currency.iso_code
        @timeout = timeout
        @fetch_rates_method_name = if oer_account_type == AccountType::FREE || oer_account_type == AccountType::DEVELOPER
          :fetch_historical_rates
        else
          :fetch_time_series_rates
        end
      end

      # Fetches the rates for all available quote currencies (for given date or for a whole month, depending on openexchangerates.org account type).
      # Fetching for all currencies or just one has the same API charge.
      #
      # It returns a +Hash+ with the rates for each quote currency and date
      # as shown in the example. Rates are +BigDecimal+.
      #
      # ==== Parameters
      #
      # - +date+ - +date+ for which the rates are requested. Minimum +date+ is January 1st 1999, as defined by the OER API (https://docs.openexchangerates.org/docs/api-introduction). Maximum +date+ is yesterday (UTC), as today's rates are not final (https://openexchangerates.org/faq/#timezone).
      #            If Enterprise or Unlimited account in openexchangerates.org, the +date+'s month is the month for which we request rates
      #
      # ==== Errors
      #
      # - Raises +ArgumentError+ when +date+ is less than January 1st 1999, or greater than yesterday (UTC)
      # - Raises +Money::RatesProvider::RequestFailed+ when the OER request fails
      #
      # ==== Examples
      #
      #   oer.fetch_rates(Date.new(2016, 10, 5))
      #   If Free or Developer account in openexchangerates.org, it will return only for the given date
      #   # => {"AED"=>{"2016-10-05"=>#<BigDecimal:7fa19a188e98,'0.3672682E1',18(36)>}, {"AFN"=>{"2016-10-05"=>#<BigDecimal:7fa19a188e98,'0.3672682E1',18(36)>}, ...
      #   If Enterprise or Unlimited account, it will return for the entire month for the given date 
      #   # => {"AED"=>{"2016-10-01"=>#<BigDecimal:7fa19a188e98,'0.3672682E1',18(36)>, "2016-10-02"=>#<BigDecimal:7fa19b11a5c8,'0.367296E1',18(36)>, ...
      def fetch_rates(date)
        if date < MIN_DATE || date > max_date
          raise ArgumentError, "Provided date #{date} for OER query should be "\
                               "between #{MIN_DATE} and #{max_date}"
        end

        response = send(@fetch_rates_method_name, date)


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

      # the API doesn't allow fetching more than a month's data.
      def fetch_time_series_rates(date)
        options = request_options

        end_of_month = Date.civil(date.year, date.month, -1)
        start_date = Date.civil(date.year, date.month, 1)
        end_date = [end_of_month, max_date].min
        options[:query][:start] = start_date
        options[:query][:end] = end_date

        response = self.class.get('/time-series.json', options)

        unless response.success?
          raise RequestFailed, "Month rates request failed for #{date} - "\
                               "Code: #{response.code} - Body: #{response.body}"
        end
        response        
      end

      def fetch_historical_rates(date)
        date_string = date.iso8601
        options = request_options
        response = self.class.get("/historical/#{date_string}.json", options)

        unless response.success?
          raise RequestFailed, "Historical rates request failed for #{date} - "\
                               "Code: #{response.code} - Body: #{response.body}"
        end

        # Making the return value comply to the same structure returned from the #fetch_month_rates method (/time-series.json API)
        { 
          'start_date' => date_string,
          'end_date' => date_string,
          'base' => response['base'],
          'rates' => {
            date_string => response['rates']
          }
        }
      end

      def request_options
        options = {
          query: {
            app_id:  @oer_app_id,
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
