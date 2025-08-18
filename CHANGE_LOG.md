# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0

### Added

- Lumberjack 2 support.

### Changed

- **Breaking Change** Changed config option `log_tag_prefix` to `log_attributes_prefix`
- **Breaking Change** Renamed `Lumberjack::Sidekiq::TagPassthroughMiddleware` to `Lumberjack::Sidekiq::AttributePassthroughMiddleware`.

## 1.0.1

### Changed

- Switched to using the standard `with_level` method for temporarily changing log levels.

## 1.0.0

### Added

- Initial release
