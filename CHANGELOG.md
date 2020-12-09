# Changelog

## 0.1.4
- Support `redis` gem versions '>=3.3', '~> 4.0'

## 0.1.3
- Support `redis` gem versions '>=3.3', '< 4.1' (#3)

## 0.1.0
- Added basic functionality and documentation.

## 0.1.1
- Added support for FREE and DEVELOPER OpenExchangeRates accounts. Downside when using these accounts is that OER rates are fetched for a single day at a time (as opposed to a whole month for more advanced plans).
- Developers have to specify `oer_account_type` during configuration.

## 0.1.2
- Updated `rubocop` gem needed for development due to low-severity security issue with version 0.46
