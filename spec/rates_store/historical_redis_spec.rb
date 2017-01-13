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
  module RatesStore
    describe HistoricalRedis do
      let(:redis_url) { "redis://localhost:#{ENV['REDIS_PORT']}" }
      let(:redis) { Redis.new(port: ENV['REDIS_PORT']) }

      let(:base_currency) { Currency.new('EUR') }
      let(:namespace) { 'currency_test' }
      let(:store) { HistoricalRedis.new(base_currency, redis_url, namespace) }
      let(:key_prefix) { 'currency_test:EUR' }

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

      after do
        keys = redis.keys("#{namespace}*")
        redis.del(keys) unless keys.empty?
      end

      describe '#add_rates' do
        let(:expected_stored_hash_usd) do
          {
            '2015-09-10' => 0.11111.to_d.to_s,
            '2015-09-11' => 0.22222.to_d.to_s,
            '2015-09-12' => 0.33333.to_d.to_s
          }
        end
        let(:expected_stored_hash_gbp) do
          {
            '2015-09-10' => 0.44444.to_d.to_s,
            '2015-09-11' => 0.55555.to_d.to_s,
            '2015-09-12' => 0.66666.to_d.to_s
          }
        end
        let(:expected_stored_hash_vnd) do
          {
            '2015-09-10' => 0.77777.to_d.to_s,
            '2015-09-11' => 0.88888.to_d.to_s,
            '2015-09-12' => 0.99999.to_d.to_s
          }
        end

        subject { store.add_rates(currency_date_rate_hash) }

        context 'when no rates exist' do
          it 'should store the values' do
            subject
            expect(redis.hgetall("#{key_prefix}:USD")).to eq expected_stored_hash_usd
            expect(redis.hgetall("#{key_prefix}:GBP")).to eq expected_stored_hash_gbp
            expect(redis.hgetall("#{key_prefix}:VND")).to eq expected_stored_hash_vnd
          end
        end

        context 'when some rates exist' do
          let(:preexistent_rates) do
            {
              'USD' => {
                '2015-09-10' => 0.12345.to_d,
                '2015-09-11' => 0.09876.to_d
              }
            }
          end

          before do
            store.add_rates(preexistent_rates)
          end

          it 'overwrites their values' do
            expect { subject }.to change { redis.hgetall("#{key_prefix}:USD") }
              .to(expected_stored_hash_usd)
          end
        end

        context 'when there is a Redis error' do
          let(:redis_url) { 'redis://localhost:1231' }

          it 'fails with RequestFailed' do
            expect { subject }.to raise_error(RatesStore::RequestFailed)
          end
        end

        context 'when base currency is included in the given currencies' do
          context 'and its rate is 1' do
            let(:currency_date_rate_hash) do
              {
                base_currency.iso_code => { '2015-09-10' => 1.0 }
              }
            end

            it 'does not fail' do
              subject
            end
          end

          context 'and its rate is not 1' do
            let(:currency_date_rate_hash) do
              {
                base_currency.iso_code => { '2015-09-10' => 0.423 }
              }
            end

            it 'fails with ArgumentError' do
              expect { subject }.to raise_error(ArgumentError)
            end
          end
        end
      end

      describe '#get_rates' do
        let(:from_currency) { Currency.new('USD') }

        subject { store.get_rates(from_currency) }

        context 'when rates exist' do
          before do
            store.add_rates(currency_date_rate_hash)
          end

          it { is_expected.to eq usd_date_rate_hash }
        end

        context "when rates don't exist" do
          it { is_expected.to eq({}) }
        end

        context 'when there is a Redis error' do
          let(:redis_url) { 'redis://localhost:1231' }

          it 'fails with RequestFailed' do
            expect { subject }.to raise_error(RatesStore::RequestFailed)
          end
        end
      end
    end
  end
end
