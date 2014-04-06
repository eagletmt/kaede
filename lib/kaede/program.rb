# coding: utf-8

module Kaede
  class Program < Struct.new(:pid, :tid, :start_time, :end_time, :channel_name, :channel_for_syoboi, :channel_for_recorder, :count, :start_offset, :subtitle, :title, :comment)
    def self.from_xml(doc)
      doc.xpath('//progitem').map do |item|
        prog = self.new
        prog.pid = item['pid'].to_i
        prog.tid = item['tid'].to_i
        prog.start_time = Time.parse(item['sttime'])
        prog.end_time = Time.parse(item['edtime'])
        prog.channel_for_syoboi = item['chid'].to_i
        prog.count = item['count'].to_i
        prog.start_offset = item['stoffset'].to_i # in second
        prog.subtitle = item['subtitle']
        prog.title = item['title']
        prog.comment = item['progcomment']
        prog
      end
    end

    def syoboi_url
      "http://cal.syoboi.jp/tid/#{tid}##{pid}"
    end

    def formatted_fname
      fname = "#{tid}_#{pid} #{title} ##{count} #{subtitle}#{comment.empty? ? '' : " (#{comment})"} at #{channel_name}"
      fname = fname.gsub('/', '／')
      if fname.bytesize >= 200
        fname = "#{tid}_#{pid} #{title} ##{count} at #{channel_name}"
      end
      fname
    end

  end
end
