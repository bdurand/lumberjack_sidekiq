# Lumberjack Sidekiq

[![Continuous Integration](https://github.com/bdurand/lumberjack_sidekiq/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_sidekiq/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_sidekiq.svg)](https://badge.fury.io/rb/lumberjack_sidekiq)

This gem provides an enhanced logging setup for [Sidekiq](https://github.com/mperham/sidekiq) using the [lumberjack](https://github.com/bdurand/lumberjack) structured logging framework. It replaces Sidekiq's default job logging behavior with one that provides rich structured logging with automatic tagging, timing information, and context propagation.

**Key Features:**

- **Structured Job Logging**: Automatically adds structured tags for job metadata (class, job ID, queue, duration, etc.)
- **Context Propagation**: Pass log tags from client to server to maintain request context across job execution
- **Flexible Configuration**: Control logging behavior per job with options for log levels, argument filtering, and custom tags
- **Performance Tracking**: Automatic timing of job execution and queue wait times

## Usage

### Job Logger

The `Lumberjack::Sidekiq::JobLogger` provides structured logging for Sidekiq jobs with automatic tagging and timing information.

To use it, configure Sidekiq to use the Lumberjack job logger:

```ruby
require 'lumberjack_sidekiq'

# Firat you'll need a Lumberjack logger instance
logger = Lumberjack::Logger.new(STDOUT)

# Configure Sidekiq to use Lumberjack
Sidekiq.configure_server do |config|
  config.logger = logger
  config[:job_logger] = Lumberjack::Sidekiq::JobLogger
end
```

The job logger automatically adds structured tags to your log entries:

- `class` - The worker class name
- `jid` - The job ID
- `bid` - The batch ID (if using Sidekiq batch)
- `queue` - The queue name
- `duration` - Job execution time in seconds
- `enqueued_ms` - Time the job was queued before execution
- `retry_count` - Number of retries (if > 0)
- `tags` - Any custom Sidekiq tags

You can add an optional prefix to all tags:

```ruby
Sidekiq.configure_server do |config|
  config[:log_tag_prefix] = "sidekiq."
end
```

### Tag Passthrough Middleware

The `Lumberjack::Sidekiq::TagPassthroughMiddleware` allows you to pass log tags from the client (where jobs are enqueued) to the server (where jobs are executed). This is useful for maintaining context like user IDs or request IDs across the job execution.

Configure the middleware on the client side:

```ruby
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    # Pass through :user_id and :request_id tags to the job logger
    chain.add(Lumberjack::Sidekiq::TagPassthroughMiddleware, :user_id, :request_id)
  end
end
```

Now when you enqueue a job with those tags in the current logging context, they will be propagated to the logs when the job runs.

```ruby
logger.tag(user_id: 123, request_id: "abc-def") do
  MyWorker.perform_async(params)
end
```

### Adding Additional Metadata

You can add additional metadata to your job logs by adding your own server middleware. Job logging sets up a tag context so any tags you add in your middleware will be included in the job log when it finishes.

Tags added before the `yield` in your middleware will be included in all logs for the job processing. Tags added after the `yield` will only be included in the final final job lifecycle event log.

```ruby
class MyLogTaggingMiddleware
  include Sidekiq::ServerMiddleware

  def call(worker, job, queue)
    # Add tag_1 to all logs for this job.
    Sidekiq.logger.tag(tag_1: job["value_1"]) if Sidekiq.logger.is_a?(Lumberjack::Logger)

    yield

    # Add tag_2 only to the final job log only.
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
    tags: {custom: "value"}  # Add custom tags to job logs
  }

  def perform(param1, param2)
    # Your job logic here
  end
end
```

### Configuration Options

You can globally disable logging job start events by setting `:skip_start_job_logging` to `true` in the Sidekiq configuration.

```ruby
Sidekiq.configure_server do |config|
  config[:skip_start_job_logging] = true
end
```

You can add a prefix to all automatically generated log tags by setting `:log_tag_prefix`.

```ruby
Sidekiq.configure_server do |config|
  config[:log_tag_prefix] = "sidekiq."
end
```

You can disable logging the enqueued time by setting `:skip_enqueued_time_logging` to `true`.

```ruby
Sidekiq.configure_server do |config|
  config[:skip_enqueued_time_logging] = true
end
```

You can disable logging any job arguments by setting `:skip_logging_arguments` to `true`.

```ruby
Sidekiq.configure_server do |config|
  config[:skip_logging_arguments] = true
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
```ruby
gem 'lumberjack_sidekiq'
```

And then execute:
```bash
$ bundle
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
