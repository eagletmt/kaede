require 'forwardable'
require 'sequel'
require 'retryable'
require 'kaede/channel'
require 'kaede/program'

module Kaede
  class Database
    extend Forwardable
    def_delegators :@db, :transaction

    def initialize(path)
      @db = Sequel.connect(path)
    end

    def prepare_tables
      @db.create_table?(:channels) do
        primary_key :id
        String :name, size: 255, null: false, unique: true
        Integer :for_recorder, null: false, unique: true
        Integer :for_syoboi, null: false, unique: true
      end
      @db.create_table?(:programs) do
        primary_key :pid
        Integer :tid, null: false
        DateTime :start_time, null: false
        DateTime :end_time, null: false
        foreign_key :channel_id, :channels
        String :count, size: 16, null: false
        Integer :start_offset, null: false
        String :subtitle, size: 255
        String :title, size: 255
        String :comment, size: 255
      end
      @db.create_table?(:jobs) do
        foreign_key :pid, :programs, primary_key: true
        DateTime :enqueued_at, null: false
        DateTime :finished_at
        DateTime :created_at, null: false
      end
      @db.create_table?(:tracking_titles) do
        Integer :tid, primary_key: true
        DateTime :created_at, null: false
      end
    end

    def get_jobs
      retry_on_disconnected do
        @db.from(:jobs).select(:pid, :enqueued_at).where(Sequel.qualify(:jobs, :enqueued_at) >= Time.now).order(:enqueued_at).to_a
      end
    end

    def update_job(pid, enqueued_at)
      retry_on_disconnected do
        @db.transaction do
          if @db.from(:jobs).where(pid: pid).select(1).first
            @db.from(:jobs).where(pid: pid).update(enqueued_at: enqueued_at)
          else
            @db.from(:jobs).insert(pid: pid, enqueued_at: enqueued_at, created_at: Time.now)
          end
        end
      end
    end

    def delete_job(pid)
      retry_on_disconnected do
        @db.from(:jobs).where(pid: pid).delete
      end
    end

    def get_program(pid)
      get_programs([pid])[pid]
    end

    def get_programs(pids)
      programs = {}
      retry_on_disconnected do
        @db.from(:programs).inner_join(:channels, [[channel_id: :id]]).where(pid: pids).each do |row|
          program = Program.new(
            row[:pid],
            row[:tid],
            row[:start_time],
            row[:end_time],
            row[:name],
            row[:for_syoboi],
            row[:for_recorder],
            row[:count],
            row[:start_offset],
            row[:subtitle],
            row[:title],
            row[:comment],
          )
          programs[program.pid] = program
        end
      end
      programs
    end

    def mark_finished(pid)
      retry_on_disconnected do
        @db.from(:jobs).where(pid: pid).update(finished_at: Time.now)
      end
    end

    def get_channels
      retry_on_disconnected do
        @db.from(:channels).map do |row|
          Channel.new(row[:id], row[:name], row[:for_recorder], row[:for_syoboi])
        end
      end
    end

    def add_channel(channel)
      retry_on_disconnected do
        @db.from(:channels).insert(name: channel.name, for_recorder: channel.for_recorder, for_syoboi: channel.for_syoboi)
      end
    end

    def update_program(program, channel)
      attributes = {
        tid: program.tid,
        start_time: program.start_time,
        end_time: program.end_time,
        channel_id: channel.id,
        count: program.count,
        start_offset: program.start_offset,
        subtitle: program.subtitle,
        title: program.title,
        comment: program.comment,
      }
      retry_on_disconnected do
        @db.transaction do
          if @db.from(:programs).where(pid: program.pid).select(1).first
            @db.from(:programs).where(pid: program.pid).update(attributes)
          else
            @db.from(:programs).insert(attributes.merge(pid: program.pid))
          end
        end
      end
    end

    def add_tracking_title(tid)
      retry_on_disconnected do
        @db.from(:tracking_titles).insert(tid: tid, created_at: Time.now)
      end
    rescue Sequel::UniqueConstraintViolation => e
      $stderr.puts "WARNING: #{e.class}: #{e.message}"
    end

    def get_tracking_titles
      retry_on_disconnected do
        @db.from(:tracking_titles).select(:tid).map do |row|
          row[:tid]
        end
      end
    end

    private

    def retry_on_disconnected(&block)
      retry_for_disconnection { retry_for_each_connection(&block) }
    end

    def retry_for_disconnection(&block)
      Retryable.retryable(
        tries: 5,
        sleep: lambda { |n| 2**n },
        on: Sequel::DatabaseDisconnectError,
        exception_cb: lambda { |e| $stderr.puts "[#{Thread.current.object_id}] retry_for_disconnection: #{e.class}: #{e.message}" },
        &block
      )
    end

    def retry_for_each_connection(&block)
      Retryable.retryable(
        tries: @db.pool.max_size,
        sleep: 0,
        on: Sequel::DatabaseDisconnectError,
        exception_cb: lambda { |e| $stderr.puts "[#{Thread.current.object_id}] retry_for_each_connection: #{e.class}: #{e.message}" },
        &block
      )
    end
  end
end
