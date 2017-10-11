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

require 'spec_helper'

class Money
  module RatesProvider
    describe OpenExchangeRates do
      let(:base_currency_iso_code) { %w(GBP EUR USD).sample }
      let(:base_currency) { Currency.wrap(base_currency_iso_code) }
      let(:date) { Date.new(2010, 10, 10) }
      let(:app_id) { SecureRandom.hex }
      let(:timeout) { 15 }
      let(:response_headers) { { 'Content-Type' => 'application/json; charset=utf-8' } }

      describe '#fetch_rates with FREE account' do
        let(:provider) { OpenExchangeRates.new(app_id, base_currency, timeout, Money::Bank::Historical::Configuration::AccountType::FREE) }
        let(:url) { 'https://openexchangerates.org/api/historical/2010-10-01.json' }
        let(:date) { Date.new(2010, 10, 01) }
        let(:query) do
          {
            app_id: app_id,
            base:   base_currency_iso_code,
          }
        end

        before do
          stub_request(:get, url).with(query: query)
                                 .to_return(status: status, body: response_body, headers: response_headers)
        end

        subject { provider.fetch_rates(date) }

        context 'when request succeeds' do
          let(:status) { 200 }
          let(:base_currency_iso_code) { 'EUR' }
          let(:response_body) do
            {
              base:       base_currency_iso_code,
              rates: {
                'VND' => 1.1,
                'USD' => 2.1,
                'CAD' => 3.1,
                'CNY' => 4.1
              }
            }.to_json
          end

          it 'format response similar to the full-month/time-series response' do
            expect(subject.keys =~ ['base', 'rates', 'start_date', 'end_date'])
          end

          it 'return rates only for given date' do
            dates = subject.map { |country, dates_hash| dates_hash.keys }.flatten.uniq
            expect(dates.size == 1)
            expect(dates.first == '2010-10-01')
          end

          it 'returns correct rates' do
            expect(subject['VND']['2010-10-01']).to eq 1.1.to_d
            expect(subject['USD']['2010-10-01']).to eq 2.1.to_d
            expect(subject['CAD']['2010-10-01']).to eq 3.1.to_d
            expect(subject['CNY']['2010-10-01']).to eq 4.1.to_d
          end
        end
      end
      

      describe '#fetch_rates with UNLIMITED account' do
        let(:provider) { OpenExchangeRates.new(app_id, base_currency, timeout, Money::Bank::Historical::Configuration::AccountType::UNLIMITED) }
        let(:url) { 'https://openexchangerates.org/api/time-series.json' }
        let(:query) do
          {
            app_id: app_id,
            base:   base_currency_iso_code,
            start:  '2010-10-01',
            end:    '2010-10-31'
          }
        end

        before do
          stub_request(:get, url).with(query: query)
                                 .to_return(status: status, body: response_body, headers: response_headers)
        end

        subject { provider.fetch_rates(date) }

        context 'when date is before 1999' do
          let(:date) { Faker::Date.between(Date.new(1900, 1, 1), Date.new(1998, 12, 31)) }
          let(:status) { 200 }
          let(:response_body) { '' }

          it 'fails with ArgumentError' do
            expect { subject }.to raise_error(ArgumentError)
          end
        end

        context 'when date is in the future' do
          let(:date) { Date.today + 2 }
          let(:status) { 200 }
          let(:response_body) { '' }

          it 'fails with ArgumentError' do
            expect { subject }.to raise_error(ArgumentError)
          end
        end

        context 'when request fails' do
          let(:status) { 400 }
          let(:response_body) { '' }

          it 'fails with RequestFailed' do
            expect { subject }.to raise_error(RatesProvider::RequestFailed)
          end
        end

        context 'when request succeeds' do
          let(:status) { 200 }

          context 'when previous months' do
            context 'when full response' do
              let(:base_currency_iso_code) { 'EUR' }
              let(:date) { Date.new(2015, 9, 29) }
              let(:query) do
                {
                  app_id: app_id,
                  base:   base_currency_iso_code,
                  start:  '2015-09-01',
                  end:    '2015-09-30'
                }
              end
              let(:response_body) { File.read('./spec/fixtures/time-series-2015-09.json') }

              it 'returns correct rates' do
                expect(subject['BZD']['2015-09-01']).to eq 2.25696.to_d
                expect(subject['AED']['2015-09-05']).to eq 4.094833.to_d
                expect(subject['QAR']['2015-09-12']).to eq 4.126591.to_d
                expect(subject['GBP']['2015-09-15']).to eq 0.734509.to_d
                expect(subject['USD']['2015-09-22']).to eq 1.112897.to_d
                expect(subject['ZWL']['2015-09-30']).to eq 360.157304.to_d
              end
            end

            context 'when partial response' do
              let(:response_body) do
                {
                  start_date: '2010-10-01',
                  end_date:   '2010-10-31',
                  base:       base_currency_iso_code,
                  rates: {
                    '2010-10-02' => {
                      'VND' => 1.1,
                      'USD' => 2.1,
                      'CAD' => 3.1,
                      'CNY' => 4.1
                    },
                    '2010-10-03' => {
                      'VND' => 1.2,
                      'USD' => 2.2,
                      'CAD' => 3.2,
                      'CNY' => 4.2
                    },
                    '2010-10-04' => {
                      'VND' => 1.3,
                      'USD' => 2.3,
                      'CAD' => 3.3,
                      'CNY' => 4.3
                    }
                  }
                }.to_json
              end
              let(:expected_result) do
                {
                  'VND' => {
                    '2010-10-02' => 1.1.to_d,
                    '2010-10-03' => 1.2.to_d,
                    '2010-10-04' => 1.3.to_d
                  },
                  'USD' => {
                    '2010-10-02' => 2.1.to_d,
                    '2010-10-03' => 2.2.to_d,
                    '2010-10-04' => 2.3.to_d
                  },
                  'CAD' => {
                    '2010-10-02' => 3.1.to_d,
                    '2010-10-03' => 3.2.to_d,
                    '2010-10-04' => 3.3.to_d
                  },
                  'CNY' => {
                    '2010-10-02' => 4.1.to_d,
                    '2010-10-03' => 4.2.to_d,
                    '2010-10-04' => 4.3.to_d
                  }
                }
              end

              it { is_expected.to eq expected_result }
            end
          end

          context 'when current month' do
            # we'll mock current time with Timecop
            let(:now) { Time.new(2016, 9, 23, 12, 0, 0) }
            let(:date) { Date.new(2016, 9, 12) }
            let(:query) do
              {
                app_id: app_id,
                base:   base_currency_iso_code,
                start:  '2016-09-01',
                  # yesterday is the max date
                end:    '2016-09-22'
              }
            end
            # doesn't matter, we're checking the query here
            let(:response_body) do
              {
                rates: {}
              }.to_json
            end
            #   {
            #     start_date: yesterday_utc.at_beginning_of_month.iso8601,
            #     end_date:   yesterday_utc.iso8601,
            #     base:       base_currency_iso_code,
            #     rates: {} # doesn't matter, we're checking the query here
            #   }.to_json
            # end

            before { Timecop.travel(now) }
            after { Timecop.return }

            it 'sets the correct end date' do
              subject
              expect(a_request(:get, url).with(query: query)).to have_been_made.once
            end
          end
        end
        

      end
    end
  end
end
