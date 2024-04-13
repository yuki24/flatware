# frozen_string_literal: true

require 'flatware/cli'
require 'flatware/rspec'
require 'flatware/rspec/formatters/console'

module Flatware
  # rspec thor command
  class CLI
    worker_option
    method_option(
      'sink-endpoint',
      type: :string,
      default: 'drbunix:flatware-sink'
    )
    desc 'rspec [FLATWARE_OPTS]', 'parallelizes rspec'
    def rspec(*rspec_args)
      job_builder = RSpec::JobBuilder.new(rspec_args, workers: workers)

      if !job_builder.seconds_per_file.empty?
        puts "Using #{job_builder.example_status_persistence_file_path} as recorded test runtime."
      else
        puts "No recorded test runtime found in #{job_builder.example_status_persistence_file_path}."
      end

      puts "#{workers} processes for #{job_builder.timed_files.size + job_builder.untimed_files.size} specs " \
           "(#{job_builder.timed_files.size} timed, #{job_builder.untimed_files.size} untimed)"

      jobs = job_builder.jobs

      jobs.each_with_index do |job, index|
        puts "Worker #{index}: #{job.id.size} examples may finish in #{job.id.sum { _1.time.to_i }.to_i}s"
        job.id.map! { _1.path }
      end

      formatter = Flatware::RSpec::Formatters::Console.new(
        ::RSpec.configuration.output_stream,
        deprecation_stream: ::RSpec.configuration.deprecation_stream
      )

      Flatware.verbose = options[:log]
      Worker.spawn count: workers, runner: RSpec, sink: options['sink-endpoint']
      start_sink(jobs: jobs, workers: workers, formatter: formatter)
    end
  end
end
