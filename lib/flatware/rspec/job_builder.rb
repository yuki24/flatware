# frozen_string_literal: true

require 'forwardable'

module Flatware
  module RSpec
    # groups spec files into one job per worker.
    # reads from persisted example statuses, if available,
    # and attempts to ballence the jobs accordingly.
    class JobBuilder
      extend Forwardable
      attr_reader :args, :workers, :configuration

      def_delegators(
        :configuration,
        :files_to_run,
        :example_status_persistence_file_path
      )

      def initialize(args, workers:)
        @args = args
        @workers = workers

        @configuration = ::RSpec.configuration
        configuration.define_singleton_method(:command) { 'rspec' }

        ::RSpec::Core::ConfigurationOptions.new(args).configure(@configuration)
      end

      def jobs
        balance_jobs(
          bucket_count: [files_to_run.size, workers].min,
          timed_files: timed_files,
          untimed_files: untimed_files
        )
      end

      def seconds_per_file
        @seconds_per_file ||= if ENV["TEST_RUNTIME"]
                                File
                                  .read(ENV["TEST_RUNTIME"])
                                  .split("\n")
                                  .to_h do |line|
                                    file_path, time = line.split(":")

                                    ["./#{file_path}", time.to_f]
                                  end
                              else
                                {}
                              end
      end

      def timed_files
        timed_and_untimed_files.first
      end

      def untimed_files
        timed_and_untimed_files.last
      end

      def timed_and_untimed_files
        @timed_and_untimed_files ||=
          files_to_run
            .map(&method(:normalize_path))
            .reduce([[], []]) do |(timed, untimed), file|
            if (time = seconds_per_file[file])
              [timed + [[file, time]], untimed]
            else
              [timed, untimed + [file]]
            end
          end
      end

      private

      def balance_jobs(bucket_count:, timed_files:, untimed_files:)
        balance_by(bucket_count, timed_files, &:last)
          .map { |bucket| bucket.map { |(file, time)| FileWithStat.new(file, time) } }
          .zip(
            round_robin(bucket_count, untimed_files)
          ).map(&:flatten)
          .map { |files| Job.new(files, args) }
      end

      def normalize_path(path)
        ::RSpec::Core::Metadata.relative_path(File.expand_path(path))
      end

      def round_robin(count, items)
        Array.new(count) { [] }.tap do |groups|
          items.each_with_index do |entry, i|
            groups[i % count] << FileWithStat.new(entry, 0)
          end
        end
      end

      def balance_by(count, items, &block)
        # find the group with the smallest sum and add it there
        Array.new(count) { [] }.tap do |groups|
          items
            .sort_by(&block)
            .reverse
            .each do |entry|
            groups.min_by do |group|
              group.map(&block).reduce(:+) || 0
            end.push(entry)
          end
        end
      end

      class FileWithStat
        attr_reader :path, :time

        def initialize (path, time)
          @path = path
          @time = time
        end
      end
    end
  end
end
