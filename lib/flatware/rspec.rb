# frozen_string_literal: true

require 'rspec/core'
require 'rspec/expectations'
require 'flatware/rspec/cli'

module Flatware
  module RSpec
    require 'flatware/rspec/formatter'
    require 'flatware/rspec/job_builder'

    module_function

    def extract_jobs_from_args(args, workers:)
      JobBuilder.new(args, workers: workers).jobs
    end

    def runner
      @runner ||= ::RSpec::Core::Runner
                    .tap { |runner| def runner.trap_interrupt(); end }
                    .new(::RSpec::Core::ConfigurationOptions.new([]))
    end

    def output_stream
      StringIO.new.tap do |output|
        output.define_singleton_method(:tty?) do
          $stdout.tty?
        end
      end
    end

    def run(job, _options = [])
      ::RSpec.configuration.deprecation_stream = StringIO.new
      ::RSpec.configuration.output_stream = output_stream
      ::RSpec.configuration.add_formatter(Flatware::RSpec::Formatter)

      runner.class.run(Array(job), $stderr, $stdout)
      ::RSpec.reset # prevents duplicate runs
    end

    def setup_suite(job)
      ::RSpec.configuration.deprecation_stream = StringIO.new
      ::RSpec.configuration.output_stream = output_stream
      ::RSpec.configuration.add_formatter(Flatware::RSpec::Formatter)

      configuration, world = runner.configuration, runner.world

      runner.configure($stderr, $stdout)
      return configuration.reporter.exit_early(exit_code) if world.wants_to_quit

      examples_count = job.id.count
      examples_passed = configuration.reporter.report(examples_count) do |reporter|
        configuration.with_suite_hooks do
          if examples_count == 0 && configuration.fail_if_no_examples
            return configuration.failure_exit_code
          end

          yield(reporter)
        end
      end

      runner.exit_code(examples_passed)
      ::RSpec.reset # prevents duplicate runs
    end

    def run_single_spec(spec_file, reporter, _options = [])
      runner.world.reset
      runner.configuration.files_or_directories_to_run = [spec_file]
      runner.configuration.load_spec_files
      runner.world.example_groups.map { |g| g.run(reporter) }.all?
    end
  end
end
