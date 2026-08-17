# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.1.0

### Added

- Log messages for job start, end, and failure can now be overridden with lambdas set in the `:job_logger_messages` configuration option (e.g. `config[:job_logger_messages] = {start: ->(job) { "Running #{job_info(job)}" }}`). The lambdas are evaluated in the context of the message formatter so they can use its helper methods.
- Job arguments can now be hidden from log messages with a deny-list set in the worker's `logging` options (e.g. `sidekiq_options logging: {hide_args: [:password]}`). Entries can be `perform` parameter names or zero based argument positions. The `args` allow-list takes precedence when both options are set. Hiding a splat parameter hides all of its values. All arguments are hidden when the parameter names cannot be resolved (e.g. jobs wrapped by ActiveJob).
- Job arguments can now be added as log attributes on every log entry made during a job by mapping `perform` parameter names to attribute names. The mapping can be set globally with the `:arg_attributes` configuration option or per worker with the `logging.arg_attributes` option; worker options take precedence. The mapped attribute names are not prefixed with `log_attribute_prefix`. The mapping is ignored when the parameter names cannot be resolved (e.g. jobs wrapped by ActiveJob).

### Changed

- Failed jobs are now logged with the original error when Sidekiq's retry handler wraps it in a `Sidekiq::JobRetry::Handled` error.
- Job argument values in log messages are now truncated to 60 characters with an ellipsis so that large values cannot overwhelm the logs. The limit does not apply to the values mapped with the `arg_attributes` option.

### Fixed

- Attributes are propagated to underlying `Lumberjack::Logger`'s when they are wrapped in a `ActiveSupport::BroadcastLogger`.
- `AttributePassthroughMiddleware` no longer mutates the job's `logging` options hash in place. Because Sidekiq merges the class-level `sidekiq_options` hash into job payloads by reference, mutating it leaked passthrough attributes from one job into all subsequent jobs of the same worker class and raced across threads pushing jobs concurrently.
- `AttributePassthroughMiddleware` no longer adds an empty `logging` hash to job payloads when there are no attributes to pass through.
- `JobLogger` no longer raises an error when a job's `logging` option is not a hash (e.g. `sidekiq_options logging: false`).
- The duration reported in end and failure log messages now matches the value in the `duration` attribute.
- The `retry_count` attribute is now logged when it is zero, which indicates the first retry of a job.

## 2.0.0

### Added

- Lumberjack 2 support.
- Added Lumberjack global context around the job logger.

### Changed

- Attributes are now passed through the logger's attribute formatter before serializing them to JSON for inclusion in job payloads.
- **Breaking Change** Updated terminology to match Lumberjack 2 change to refer to "attributes" rather than "tags".
  - Changed config option `log_tag_prefix` to `log_attributes_prefix`
  - Renamed `Lumberjack::Sidekiq::TagPassthroughMiddleware` to `Lumberjack::Sidekiq::AttributePassthroughMiddleware`.

## 1.0.1

### Changed

- Switched to using the standard `with_level` method for temporarily changing log levels.

## 1.0.0

### Added

- Initial release
