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
  module Bank
    describe Historical do
      let(:base_currency) { Currency.new('EUR') }
      let(:redis_url) { "redis://localhost:#{ENV['REDIS_PORT']}" }
      let(:redis) { Redis.new(port: ENV['REDIS_PORT']) }
      let(:redis_namespace) { 'currency_test' }
      let(:bank) { Historical.instance }

      before do
        Historical.configure do |config|
          config.base_currency = base_currency
          config.redis_url = redis_url
          config.redis_namespace = redis_namespace
          config.oer_app_id = SecureRandom.hex
          config.timeout = 20
        end
      end

      after do
        keys = redis.keys("#{redis_namespace}*")
        redis.del(keys) unless keys.empty?
      end

      describe '#add_rates' do
        let(:usd_date_rate_hash) do
          {
            '2015-09-10' => 0.11111.to_d,
            '2015-09-11' => 0.22222.to_d,
            '2015-09-12' => 0.33333.to_d
          }
        end
        let(:currency_date_rate_hash) do
          {
            'USD' => usd_date_rate_hash,
            'GBP' => {
              '2015-09-10' => 0.44444.to_d,
              '2015-09-11' => 0.55555.to_d,
              '2015-09-12' => 0.66666.to_d
            },
            'VND' => {
              '2015-09-10' => 0.77777.to_d,
              '2015-09-11' => 0.88888.to_d,
              '2015-09-12' => 0.99999.to_d
            }
          }
        end
        # it's pointing to the same cache as the one in bank
        let(:new_store) do
          RatesStore::HistoricalRedis.new(base_currency, redis_url, redis_namespace)
        end

        subject { bank.add_rates(currency_date_rate_hash) }

        it 'sets the rates' do
          subject
          cached_rates = new_store.get_rates(Currency.new('USD'))

          expect(cached_rates).to eq usd_date_rate_hash
        end
      end

      describe '#add_rate' do
        let(:rate) { rand }

        # it's pointing to the same cache as the one in bank
        let(:new_store) do
          RatesStore::HistoricalRedis.new(base_currency, redis_url, redis_namespace)
        end
        let(:datetime) { Time.utc(2017, 1, 4, 13, 0, 0) }

        subject { bank.add_rate(from_currency, to_currency, rate, datetime) }

        context 'when base currency == from_currency' do
          let(:from_currency) { 'EUR' }
          let(:to_currency) { Money::Currency.new('USD') }

          it "sets date's rate" do
            subject
            cached_rates = new_store.get_rates(to_currency)

            cached_rate = cached_rates['2017-01-04']
            expect(cached_rate).to be_within(0.00000001).of(rate)
          end
        end

        context 'when base currency == to_currency' do
          let(:from_currency) { Money::Currency.new('USD') }
          let(:to_currency) { Money::Currency.new('EUR') }

          it "sets date's rate as the inverse" do
            subject
            cached_rates = new_store.get_rates(from_currency)

            cached_rate = cached_rates['2017-01-04']
            expect(cached_rate).to be_within(0.00000001).of(1 / rate)
          end
        end

        context 'when base currency does not match either of the passed currencies' do
          let(:from_currency) { Money::Currency.new('USD') }
          let(:to_currency) { 'GBP' }

          it 'fails with ArgumentError' do
            expect { subject }.to raise_error ArgumentError
          end
        end

        context 'when datetime is a Date' do
          let(:datetime) { Faker::Date.between(Date.today - 100, Date.today + 100) }
          let(:from_currency) { 'EUR' }
          let(:to_currency) { Money::Currency.new('USD') }

          it "sets yesterday's rate" do
            subject
            cached_rates = new_store.get_rates(to_currency)

            cached_rate = cached_rates[datetime.iso8601]
            expect(cached_rate).to be_within(0.00000001).of(rate)
          end
        end

        context 'when datetime is not passed' do
          let(:from_currency) { 'EUR' }
          let(:to_currency) { Money::Currency.new('USD') }
          let(:now) { Time.utc(2017, 12, 5, 13, 0, 0) }

          subject { bank.add_rate(from_currency, to_currency, rate) }

          before { Timecop.travel(now) }
          after { Timecop.return }

          it "sets yesterday's rate" do
            subject
            cached_rates = new_store.get_rates(to_currency)

            cached_rate = cached_rates['2017-12-04']
            expect(cached_rate).to be_within(0.00000001).of(rate)
          end
        end
      end

      describe '#get_rate' do
        let(:from_currency) { 'EUR' }
        let(:to_currency) { Money::Currency.new('USD') }
        let(:rate) { rand }

        context 'when datetime is passed' do
          subject { bank.get_rate(from_currency, to_currency, datetime) }

          before { bank.add_rate(from_currency, to_currency, rate, datetime) }

          context 'and it is a Time' do
            let(:datetime) { Time.utc(2016, 3, 12, 14, 0, 0) }

            it 'returns the correct rate' do
              expect(subject).to be_within(0.00000001).of(rate)
            end
          end

          context 'and it is a Date' do
            let(:datetime) { Faker::Date.between(Date.today - 100, Date.today + 100) }

            it 'returns the correct rate' do
              expect(subject).to be_within(0.00000001).of(rate)
            end
          end
        end

        context 'when datetime is not passed' do
          subject { bank.get_rate(from_currency, to_currency) }

          before { bank.add_rate(from_currency, to_currency, rate) }

          it "returns yesterday's rate" do
            expect(subject).to be_within(0.00000001).of(rate)
          end
        end
      end

      describe '#exchange_with_historical' do
        let(:from_currency) { Currency.wrap('USD') }
        let(:from_money) { Money.new(10_000, from_currency) }
        let(:to_currency) { Currency.wrap('GBP') }
        let(:datetime) { Faker::Time.between(Date.today - 300, Date.today - 2) }
        let(:date) { datetime.utc.to_date }
        let(:from_currency_base_rate) { 1.1250721881474421.to_d }
        let(:to_currency_base_rate) { 0.7346888078084116.to_d }
        let(:from_currency_base_rates) do
          {
            (date - 1).iso8601 => rand,
            date.iso8601       => from_currency_base_rate,
            (date + 1).iso8601 => rand
          }
        end
        let(:to_currency_base_rates) do
          {
            (date - 1).iso8601 => rand,
            date.iso8601       => to_currency_base_rate,
            (date + 1).iso8601 => rand
          }
        end
        let(:expected_result) { Money.new(6530, to_currency) }

        before do
          allow_any_instance_of(RatesStore::HistoricalRedis).to receive(:get_rates)
            .with(from_currency).and_return(from_currency_base_rates_store)
          allow_any_instance_of(RatesStore::HistoricalRedis).to receive(:get_rates)
            .with(to_currency).and_return(to_currency_base_rates_store)
          allow_any_instance_of(RatesProvider::OpenExchangeRates)
            .to receive(:fetch_month_rates).with(date).and_return(rates_provider)
        end

        subject { bank.exchange_with_historical(from_money, to_currency, datetime) }

        describe 'to_currency parameter' do
          let(:from_currency_base_rates_store) { from_currency_base_rates }
          let(:to_currency_base_rates_store) { to_currency_base_rates }
          let(:rates_provider) { nil }

          context 'when iso code string' do
            let(:to_currency) { 'GBP' }

            it { is_expected.to eq expected_result }
          end
        end

        describe 'datetime type' do
          let(:datetime) { Faker::Time.between(Date.today - 300, Date.today - 2) }
          let(:date) { datetime.utc.to_date }
          let(:from_currency_base_rates_store) { from_currency_base_rates }
          let(:to_currency_base_rates_store) { to_currency_base_rates }
          let(:rates_provider) { nil }

          it 'returns same result when passing a date or time on that date' do
            time_result = bank.exchange_with_historical(from_money, to_currency, datetime)
            date_result = bank.exchange_with_historical(from_money, to_currency, date)

            expect(time_result).to eq date_result
          end
        end

        describe 'selecting data source' do
          context 'when both rates exist in Redis' do
            let(:from_currency_base_rates_store) { from_currency_base_rates }
            let(:to_currency_base_rates_store) { to_currency_base_rates }
            let(:rates_provider) { nil }

            it { is_expected.to eq expected_result }
          end

          context "when from_currency rate doesn't exist in Redis" do
            let(:from_currency_base_rates_store) { nil }
            let(:to_currency_base_rates_store) { to_currency_base_rates }
            let(:rates_provider) { { from_currency.iso_code => from_currency_base_rates } }

            it { is_expected.to eq expected_result }
          end

          context 'when from_currency rate exists in Redis for other dates' do
            let(:from_currency_base_rates_other_dates) do
              {
                (date - 3).iso8601 => rand,
                (date - 2).iso8601 => rand,
                (date - 1).iso8601 => rand
              }
            end
            let(:from_currency_base_rates_store) { from_currency_base_rates_other_dates }
            let(:to_currency_base_rates_store) { to_currency_base_rates }
            let(:rates_provider) { { from_currency.iso_code => from_currency_base_rates } }

            it { is_expected.to eq expected_result }
          end

          context "when to_currency rate doesn't exist in Redis" do
            let(:from_currency_base_rates_store) { from_currency_base_rates }
            let(:to_currency_base_rates_store) { nil }
            let(:rates_provider) { { to_currency.iso_code => to_currency_base_rates } }

            it { is_expected.to eq expected_result }
          end

          context 'when to_currency rate exists in Redis for other dates' do
            let(:to_currency_base_rates_other_dates) do
              {
                (date + 1).iso8601 => rand,
                (date + 2).iso8601 => rand,
                (date + 3).iso8601 => rand
              }
            end
            let(:from_currency_base_rates_store) { from_currency_base_rates }
            let(:to_currency_base_rates_store) { to_currency_base_rates_other_dates }
            let(:rates_provider) { { to_currency.iso_code => to_currency_base_rates } }

            it { is_expected.to eq expected_result }
          end

          context 'when neither of the rates exists in Redis' do
            let(:from_currency_base_rates_store) { nil }
            let(:to_currency_base_rates_store) { nil }
            let(:rates_provider) do
              {
                from_currency.iso_code => from_currency_base_rates,
                to_currency.iso_code   => to_currency_base_rates
              }
            end

            it { is_expected.to eq expected_result }
          end

          context 'when from_currency == to_currency' do
            let(:to_currency) { from_money.currency }
            let(:from_currency_base_rates_store) { nil }
            let(:to_currency_base_rates_store) { nil }
            let(:rates_provider) { nil }
            let(:expected_result) { from_money }

            it { is_expected.to eq expected_result }
          end

          context 'when from_currency == base_currency' do
            let(:from_money) { Money.new(10_000, base_currency) }
            let(:from_currency_base_rates_store) { nil }
            let(:to_currency_base_rates_store) { to_currency_base_rates }
            let(:rates_provider) { nil }
            let(:expected_result) { Money.new(7347, to_currency) }

            it { is_expected.to eq expected_result }
          end

          context 'when to_currency == base_currency' do
            let(:to_currency) { base_currency }
            let(:from_currency_base_rates_store) { from_currency_base_rates }
            let(:to_currency_base_rates_store) { nil }
            let(:rates_provider) { nil }
            let(:expected_result) { Money.new(8888, to_currency) }

            it { is_expected.to eq expected_result }
          end
        end

        # taken from real rates from XE.com
        describe 'money conversion' do
          let(:from_currency_base_rates_store) { from_currency_base_rates }
          let(:to_currency_base_rates_store) { to_currency_base_rates }
          let(:rates_provider) { nil }

          context 'for rates example 1' do
            let(:from_currency) { Currency.wrap('USD') }
            let(:from_money) { Money.new(500_00, from_currency) }
            let(:to_currency) { Currency.wrap('GBP') }
            let(:from_currency_base_rate) { 1.13597.to_d }
            let(:to_currency_base_rate) { 0.735500.to_d }
            let(:expected_result) { Money.new(323_73, to_currency) }

            it { is_expected.to eq expected_result }
          end

          context 'for rates example 2' do
            let(:from_currency) { Currency.wrap('INR') }
            let(:from_money) { Money.new(6_516_200, from_currency) }
            let(:to_currency) { Currency.wrap('CAD') }
            let(:from_currency_base_rate) { 73.5602.to_d }
            let(:to_currency_base_rate) { 1.46700.to_d }
            let(:expected_result) { Money.new(1_299_52, to_currency) }

            it { is_expected.to eq expected_result }
          end

          # VND has no decimal places
          context 'for rates example 3' do
            let(:from_currency) { Currency.wrap('SGD') }
            let(:from_money) { Money.new(345_67, from_currency) }
            let(:to_currency) { Currency.wrap('VND') }
            let(:from_currency_base_rate) { 1.57222.to_d }
            let(:to_currency_base_rate) { 25_160.75.to_d }
            let(:expected_result) { Money.new(5_531_870, to_currency) }

            it { is_expected.to eq expected_result }
          end

          # KWD has 3 decimal places
          context 'for rates example 4' do
            let(:from_currency) { Currency.wrap('CNY') }
            let(:from_money) { Money.new(987_654, from_currency) }
            let(:to_currency) { Currency.wrap('KWD') }
            let(:from_currency_base_rate) { 7.21517.to_d }
            let(:to_currency_base_rate) { 0.342725.to_d }
            let(:expected_result) { Money.new(469_142, to_currency) }

            it { is_expected.to eq expected_result }
          end
        end

        context 'when OER client fails with ArgumentError' do
          let(:datetime) { Faker::Time.between(Date.new(1990, 1, 1), Date.new(1998, 12, 31)) }
          let(:from_currency_base_rates_store) { nil }
          let(:to_currency_base_rates_store) { nil }
          let(:rates_provider) { nil }

          before do
            # unstub and let it blow up
            allow_any_instance_of(RatesProvider::OpenExchangeRates)
              .to receive(:fetch_month_rates).and_call_original
          end

          it 'fails' do
            expect { subject }.to raise_error(ArgumentError)
          end
        end
      end

      describe '#exchange_with' do
        let(:from_currency) { Currency.wrap('USD') }
        let(:from_money) { Money.new(10_000, from_currency) }
        let(:to_currency) { Currency.wrap('GBP') }
        let(:utc_date) { Time.now.utc.to_date }
        let(:from_currency_base_rate) { 1.1250721881474421.to_d }
        let(:to_currency_base_rate) { 0.7346888078084116.to_d }
        let(:from_currency_base_rates_store) do
          {
            (utc_date - 3).iso8601 => rand,
            (utc_date - 2).iso8601 => rand,
            (utc_date - 1).iso8601 => from_currency_base_rate
          }
        end
        let(:to_currency_base_rates_store) do
          {
            (utc_date - 3).iso8601 => rand,
            (utc_date - 2).iso8601 => rand,
            (utc_date - 1).iso8601 => to_currency_base_rate
          }
        end
        let(:expected_result) { Money.new(6530, to_currency) }

        before do
          allow_any_instance_of(Money::RatesStore::HistoricalRedis).to receive(:get_rates)
            .with(from_currency).and_return(from_currency_base_rates_store)
          allow_any_instance_of(Money::RatesStore::HistoricalRedis).to receive(:get_rates)
            .with(to_currency).and_return(to_currency_base_rates_store)
        end

        subject { bank.exchange_with(from_money, to_currency) }

        it "selects yesterday's rates" do
          expect(subject).to eq expected_result
        end
      end
    end
  end

  describe Money do
    describe '#exchange_with_historical' do
      let(:base_currency) { Currency.new('EUR') }
      let(:redis_url) { "redis://localhost:#{ENV['REDIS_PORT']}" }
      let(:redis_namespace) { 'currency_test' }
      let(:rates) do
        {
          'USD' => { '2015-09-10' => 0.11 },
          'GBP' => { '2015-09-10' => 0.44 }
        }
      end
      let(:money) { Money.new(100_00, 'USD') }
      let(:to_currency) { Money::Currency.new('GBP') }
      let(:datetime) { Date.new(2015, 9, 10) }

      before do
        Bank::Historical.configure do |config|
          config.base_currency = base_currency
          config.redis_url = redis_url
          config.redis_namespace = redis_namespace
        end

        Bank::Historical.instance.add_rates(rates)
      end

      subject { money.exchange_to_historical(to_currency, datetime) }

      # on Sept 10th, 100 EUR = 100 / 0.11 USD = 100 / 0.11 * 0.44 GBP = 400 GBP
      it { is_expected.to eq Money.new(400_00, 'GBP') }
    end
  end
end
