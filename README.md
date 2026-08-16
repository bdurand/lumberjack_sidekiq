# Lumberjack Sidekiq

[![Continuous Integration](https://github.com/bdurand/lumberjack_sidekiq/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_sidekiq/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_sidekiq.svg)](https://badge.fury.io/rb/lumberjack_sidekiq)

This gem provides an enhanced logging setup for [Sidekiq](https://github.com/mperham/sidekiq) using the [lumberjack](https://github.com/bdurand/lumberjack) structured logging framework. It replaces Sidekiq's default job logging behavior with one that provides rich structured logging with automatic tagging, timing information, and context propagation.

**Key Features:**

- **Structured Job Logging**: Automatically adds structured attributes for job metadata (class, job ID, queue, duration, etc.)
- **Context Propagation**: Pass log attributes from client to server to maintain request context across job execution
- **Flexible Configuration**: Control logging behavior per job with options for log levels, argument filtering, and custom attributes
- **Performance Tracking**: Automatic timing of job execution and queue wait times

## Usage

### Job Logger

The `Lumberjack::Sidekiq::JobLogger` provides structured logging for Sidekiq jobs with automatic tagging and timing information.

To use it, configure Sidekiq to use the Lumberjack job logger:

```ruby
require 'lumberjack_sidekiq'

# First you'll need a Lumberjack logger instance
logger = Lumberjack::Logger.new(STDOUT)

# Configure Sidekiq to use Lumberjack
Sidekiq.configure_server do |config|
  config.logger = logger
  config[:job_logger] = Lumberjack::Sidekiq::JobLogger
end
```

The job logger automatically adds structured attributes to your log entries:

- `class` - The worker class name
- `jid` - The job ID
- `bid` - The batch ID (if using Sidekiq batch)
- `queue` - The queue name
- `duration` - Job execution time in seconds
- `enqueued_ms` - Time the job was queued before execution
- `retry_count` - Number of retries (if > 0)
- `attributes` - Any custom Sidekiq attributes

You can add an optional prefix to all attributes:

```ruby
Sidekiq.configure_server do |config|
  config[:log_attribute_prefix] = "sidekiq."
end
```

### Attribute Passthrough Middleware

The `Lumberjack::Sidekiq::AttributePassthroughMiddleware` allows you to pass log attributes from the client (where jobs are enqueued) to the server (where jobs are executed). This is useful for maintaining context like user IDs or request IDs across the job execution.

Configure the middleware on the client side:

```ruby
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    # Pass through :user_id and :request_id attributes to the job logger
    chain.add(Lumberjack::Sidekiq::AttributePassthroughMiddleware, :user_id, :request_id)
  end
end
```

Now when you enqueue a job with those attributes in the current logging context, they will be propagated to the logs when the job runs.

```ruby
logger.tag(user_id: 123, request_id: "abc-def") do
  MyWorker.perform_async(params)
end
```

### Adding Additional Metadata

You can add additional metadata to your job logs by adding your own server middleware. Job logging sets up an attribute context so any attributes you add in your middleware will be included in the job log when it finishes.

Attributes added before the `yield` in your middleware will be included in all logs for the job processing. Attributes added after the `yield` will only be included in the final job lifecycle event log.

```ruby
class MyLogTaggingMiddleware
  include Sidekiq::ServerMiddleware

  def call(worker, job, queue)
    # Add tag_1 to all logs for this job.
    Sidekiq.logger.tag(tag_1: job["value_1"]) if Sidekiq.logger.is_a?(Lumberjack::Logger)

    yield

    # Add tag_2 to the final job log only.
    Sidekiq.logger.tag(tag_2: job["value_2"]) if Sidekiq.logger.is_a?(Lumberjack::Logger)
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add MyLogTaggingMiddleware
  end
end
```

### Job-Level Logging Options

You can control logging behavior on a per-job basis by setting logging options:

```ruby
class MyWorker
  include Sidekiq::Worker

  sidekiq_options logging: {
    level: "warn",           # Set log level for this job
    skip: false,             # Skip logging lifecycle events for this job
    skip_start: true,        # Skip the "Start job" lifecycle log message
    args: ["param1"],        # Only log specific arguments by name; can specify false to omit all args
    hide_args: [:param2],    # Hide specific arguments by name or position; args takes precedence when both are set
    arg_attributes: {param1: "param.one"},  # Map perform arguments to log attributes on every entry in the job
    attributes: {custom: "value"}  # Add custom attributes to job logs
  }

  def perform(param1, param2)
    # Your job logic here
  end
end
```

The `arg_attributes` mapping can also be set globally for all workers with the `:arg_attributes` configuration option. Worker options take precedence over the global mapping. The mapped attribute names are used as given and are not prefixed with `:log_attribute_prefix`.

```ruby
Sidekiq.configure_server do |config|
  config[:arg_attributes] = {user_id: "user.id"}
end
```

### Configuration Options

You can globally disable logging job start events by setting `:skip_start_job_logging` to `true` in the Sidekiq configuration.

```ruby
Sidekiq.configure_server do |config|
  config[:skip_start_job_logging] = true
end
```

You can add a prefix to all automatically generated log attributes by setting `:log_attribute_prefix`.

```ruby
Sidekiq.configure_server do |config|
  config[:log_attribute_prefix] = "sidekiq."
end
```

You can disable logging the enqueued time by setting `:skip_enqueued_time_logging` to `true`.

```ruby
Sidekiq.configure_server do |config|
  config[:skip_enqueued_time_logging] = true
end
```

You can disable logging any job arguments by setting `:skip_logging_job_arguments` to `true`.

```ruby
Sidekiq.configure_server do |config|
  config[:skip_logging_job_arguments] = true
end
```

You can override the log messages for job lifecycle events with the `:job_logger_messages` option. You can use this if your existing log processing pipeline is expecting specific message formats. Any messages you don't override will use the default format.

```ruby
Sidekiq.configure_server do |config|
  config[:job_logger_messages] = {
    start: ->(job) { "Running #{job_info(job)}" },
    end: ->(job, elapsed_time) { "Completed #{job_info(job)} in #{(elapsed_time * 1000).round(1)}ms" },
    failed: ->(job, error, elapsed_time) { "#{worker_class(job)} raised #{error.class.name}: #{error.message}" }
  }
end
```

Each lambda is passed the job hash, plus the elapsed time in seconds for `end` and the error and elapsed time for `failed`. Lambdas that don't need the trailing arguments can declare fewer parameters:

```ruby
config[:job_logger_messages] = {end: ->(job) { "Completed #{job_info(job)}" }}
```

The lambdas are evaluated in the context of the message formatter, so they can use its helper methods:

- `job_info(job)` - The worker class name and arguments (i.e. `MyWorker.perform("foo", 12)`)
- `worker_class(job)` - The worker class name, honoring the `display_class` and `wrapped` job keys
- `job_display_args(job)` - The job arguments as an array of strings, with the worker's `logging: {args: ...}` filtering applied

For full control over message formatting, you can implement your own `Lumberjack::Sidekiq::MessageFormatter` and set it in the configuration.

```ruby
Sidekiq.configure_server do |config|
  config[:job_logger_message_formatter] = MyCustomMessageFormatter.new(config)
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "lumberjack_sidekiq"
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install lumberjack_sidekiq
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
