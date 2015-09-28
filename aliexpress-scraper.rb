require 'bundler/setup'

require 'fileutils'
require 'colorize'

require './lib/scraper.rb'
require './lib/exporter.rb'

MULTIPLE_PRODUCTS = 20
PRICE_MULTIPLIER = 0.3
CSV_DELIMITER = ','
MIN_PRICE = nil
MAX_PRICE = nil
PRICE_INCREMENT = 0.01
PRICE_AS_BRL = false

begin
    search_urls = begin
        tmp_lines = []
        File.open('urls.txt').each_line {|line| tmp_lines << line.strip}
        tmp_lines
    rescue
        []
    end

    puts "#{search_urls.size} urls found".white

    argument = ARGV[0] || nil
    PAGE_LIMIT = ARGV[1] ? ARGV[1].to_i : -1

    search_urls.each do |search_url|
        case argument
        when 'drop'
            puts "Removing database and images...".white

            puts "[rm -rf /tmp/scraper/aliexpress]".white
            FileUtils.rm_rf('/tmp/scraper/aliexpress')
            puts "[rm -rf local/db/*]".white
            FileUtils.rm_rf('local/db')
            FileUtils.mkdir_p('local/db')

            puts "Done.".white
        when 'export'
            begin
                Exporter.export_search_url(search_url)
            rescue StandardError => e
                puts "Error: #{e.message}".red
            rescue
            end
        else
            begin
                Scraper.scrape_search_url(search_url)
                Exporter.export_search_url(search_url)
            rescue StandardError => e
                puts "Error: #{e.message}".red
            end
        end
    end
rescue Interrupt
    puts "Killed!".red
end