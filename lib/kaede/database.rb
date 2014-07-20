require 'forwardable'
require 'sequel'
require 'kaede/channel'
require 'kaede/program'

module Kaede
  class Database
    extend Forwardable
    def_delegators :@db, :transaction

    def initialize(path)
      @db = Sequel.connect(path)
      prepare_tables
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
    private :prepare_tables

    def get_jobs
      @db.from(:jobs).select(:pid, :enqueued_at).where(finished_at: nil).where(Sequel.qualify(:jobs, :enqueued_at) >= Time.now).order(:enqueued_at).to_a
    end

    def update_job(pid, enqueued_at)
      @db.transaction do
        begin
          @db.from(:jobs).insert(pid: pid, enqueued_at: enqueued_at, created_at: Time.now)
        rescue Sequel::UniqueConstraintViolation
          @db.from(:jobs).where(pid: pid).update(enqueued_at: enqueued_at)
        end
      end
    end

    def delete_job(pid)
      @db.from(:jobs).where(pid: pid).delete
    end

    def get_program(pid)
      get_programs([pid])[pid]
    end

    def get_programs(pids)
      programs = {}
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
      programs
    end

    def mark_finished(pid)
      @db.from(:jobs).where(pid: pid).update(finished_at: Time.now)
    end

    def get_channels
      @db.from(:channels).map do |row|
        Channel.new(row[:id], row[:name], row[:for_recorder], row[:for_syoboi])
      end
    end

    def add_channel(channel)
      @db.from(:channels).insert(name: channel.name, for_recorder: channel.for_recorder, for_syoboi: channel.for_syoboi)
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
      @db.transaction do
        begin
          @db.from(:programs).insert(attributes.merge(pid: program.pid))
        rescue Sequel::UniqueConstraintViolation
          @db.from(:programs).where(pid: program.pid).update(attributes)
        end
      end
    end

    def add_tracking_title(tid)
      @db.from(:tracking_titles).insert(tid: tid, created_at: Time.now)
    end

    def get_tracking_titles
      @db.from(:tracking_titles).select(:tid).map do |row|
        row[:tid]
      end
    end
  end
end
