require 'nokogiri'
require 'open-uri'
require 'json'
require 'fileutils'
require 'colorize'

require './lib/database.rb'

class Scraper
    def self.scrape_search_url(url, price_range=nil)
        url = self.set_params(url)

        puts "- #{url}".white

        category = Database.get_category(url)

        min_price = MIN_PRICE || self.get_min_price(url)
        max_price = MAX_PRICE || self.get_max_price(url)

        puts "[#{category[:name]}] Scanning #{PAGE_LIMIT < 0 ? 'all' : PAGE_LIMIT == 0 ? 'no' : PAGE_LIMIT} pages. Min Price = #{min_price}, Max Price = #{max_price}, Increment = #{PRICE_INCREMENT}".yellow

        if PAGE_LIMIT != 0
            self.collect_product_ids_using_price_range(url, category, min_price, max_price, PRICE_INCREMENT)
        end

        self.scrape_products(category)
    end

    def self.collect_product_ids_using_price_range(url, category, min_price, max_price, price_increment)
        price_range = (min_price..max_price).step(price_increment).to_a
        price_range.each_with_index do |price, i|
            param_min_price = price.round(2).to_s
            param_max_price = (price_range[i+1] - 0.01).round(2).to_s

            puts "[#{category[:name]}] Price Range = #{param_min_price} - #{param_max_price}".yellow

            url = if url.include?('minPrice=')
                url.gsub(/minPrice=(.*?)&+/, '') + '&minPrice=' + param_min_price
            else
                url + (url.include?('?') ? '&' : '?') + 'minPrice=' + param_min_price
            end

            url = if url.include?('maxPrice=')
                url.gsub(/maxPrice=(.*?)&+/, '') + '&maxPrice=' + param_max_price
            else
                url + (url.include?('?') ? '&' : '?') + 'maxPrice=' + param_max_price
            end

            self.collect_product_ids(url, 1, category)
        end
    end

    def self.collect_product_ids(url, page_number, category)
        puts "[#{category[:name]}] page ##{page_number} (#{url})".white

        html = Nokogiri::HTML(open(url))

        products = []
        html.css('li.list-item').each do |product_html|
            aliexpress_id = product_html.css('input.atc-product-id[type=hidden]').attr('value').value
            product_url = product_html.css('a.product').attr('href').value

            product_data = {
                aliexpress_id: aliexpress_id,
                category_id: category[:_id],
                url: product_url,
                scraped: false,
            }

            products << product_data
        end

        inserted_products_count = Database.insert_products(products, category)
        puts "[#{category[:name]}] Added #{inserted_products_count.to_i} products".yellow

        if products.any?
            unless html.css('span.page-end.ui-pagination-next.ui-pagination-disabled').any? or (PAGE_LIMIT > -1 && page_number >= PAGE_LIMIT)
                next_page_url = html.css('a.page-next.ui-pagination-next').attr('href').value
                self.collect_product_ids(next_page_url, page_number+1, category)
            end
        end
    end

    def self.scrape_products(category)
        products = Database.get_products_to_scrape(category[:_id])
        product_ids = products.map {|p| p[:_id]}

        total_products = product_ids.size
        puts "[#{category[:name]}] Scraping #{total_products} products (multiple = #{MULTIPLE_PRODUCTS})".yellow

        product_ids_threaded = product_ids.each_slice(MULTIPLE_PRODUCTS).to_a

        product_ids_threaded.each do |product_ids|
            puts "[#{category[:name]}] Scraping group of #{product_ids.size} products".white

            start = Time.now
            product_ids.map do |product_id|
                Thread.new do
                    begin
                        product = Database.products.find(_id: product_id).limit(1).first
                        total_products -= 1
                        self.scrape_product(product, category, total_products)
                    rescue StandardError => e
                        puts "[#{category[:name]}] #{product[:aliexpress_id]} (#{e.message})".red
                    end
                end
            end.each(&:join)

            puts "[#{category[:name]}] Took #{(Time.now - start).to_i} seconds to scrape #{product_ids.size} products".white
        end
    end

    def self.scrape_product(product, category, remaining)
        html = Nokogiri::HTML(open(product[:url]))

        product_data = {
            aliexpress_id: product[:aliexpress_id],
            category_id: product[:category_id],
            url: product[:url],
            scraped: true,
            description: nil,
            short_description: 'N/A',
            category: [],
            image_urls: [],
            images: [],
            attributes: [],
            option_types: [],
            count_price_modifiers: 0,
            has_sku: true
        }

        product_data[:title] = html.css('h1.product-name[itemprop=name]').text
        product_data[:seller_name] ||= html.css('a.store-lnk').attr('title').value
        categories = html.css('.ui-breadcrumb a').map(&:text)
        product_data[:category] = categories[2, categories.size]

        min_price_regex = /.*window\.runParams\.minPrice=\"(.*)\".*/i
        min_price_matches = min_price_regex.match(html.to_s)
        if min_price_matches && min_price_matches.size == 2
            product_data[:min_price] = min_price_matches[1]
        else
            raise StandardError.new("min_price")
        end

        max_price_regex = /.*window\.runParams\.maxPrice=\"(.*)\".*/i
        max_price_matches = max_price_regex.match(html.to_s)
        if max_price_matches and max_price_matches.size == 2
            product_data[:max_price] = max_price_matches[1]
        else
            raise StandardError.new("max_price")
        end

        product_data[:image_urls] = html.css('ul.image-nav li.image-nav-item span img').map {|img| img.attr('src').gsub(/_50x50\..*/, '')}

        if product_data[:image_urls].empty?
            product_data[:image_urls] = html.css('img[data-role=thumb]').map {|img| img.attr('src').gsub(/_350x350\..*/, '')}
        end

        sku_regex = /var skuProducts=(.*);/i
        sku_matches = sku_regex.match(html.to_s)
        sku_prop_ids = []
        sku_properties = []

        if sku_matches && sku_matches.size == 2 && JSON.parse(sku_matches[1])[0]['skuAttr']
            JSON.parse(sku_matches[1]).each do |sku|
                sku_attr = []
                sku['skuAttr'].split(';').each do |a|
                    temp = []
                    a.split(':').each do |b|
                        b = b[0, b.index('#')] if b.include?('#')
                        temp << b
                    end

                    sku_attr << temp.join(':')
                end

                sku_attr = sku_attr.join(';')
                sku_properties << {
                        attr: sku_attr,
                        prop_ids: sku['skuPropIds'],
                        price: sku['skuVal']['skuPrice']
                }
            end

            product_data[:sku_properties] = sku_properties
            sku_prop_ids = sku_properties[0][:attr].split(';').map {|attr| attr.split(':')[0]}
        else
            product_data[:has_sku] = false
            sku_properties = []
            product_data[:sku_properties] = []
        end

        html.css('#product-info-sku dl').each do |dl|
            attribute_title = dl.css('dt').first.text.strip.gsub(/\:/, '')
            attribute_values = []

            attribute_type = ''
            if dl.css('ul').first.attr('class').include?('sku-color')
                attribute_type = 'color'
            elsif dl.css('ul').first.attr('class').include?('sku-checkbox')
                attribute_type = 'checkbox'
            else
                raise StandardError.new("Invalid option type")
            end

            sku_prop_id = dl.css('ul').first.attr('data-sku-prop-id')

            dl.css('li a').each do |a|
                sku_id = /^sku\-\d+\-(.*)$/.match(a.attr('id'))[1]

                if attribute_type == 'color'
                    attribute_values << {
                        url: a.css('img').first ? a.css('img').first.attr('bigpic') : nil,
                        thumb_url: a.css('img').first ? a.css('img').first.attr('src') : nil,
                        title: a.attr('title'),
                        value: a.attr('title'),
                        sku_id: sku_id,
                    }
                else
                    attribute_values << {
                        value: a.text,
                        title: a.text,
                        sku_id: sku_id,
                    }
                end
            end

            product_data[:option_types] << {
                sku_prop_id: sku_prop_id,
                title: attribute_title,
                type: attribute_type,
                price_changed: false,
                values: attribute_values,
            }
        end

        product_data[:option_types].select {|option_type| !option_type[:sku_prop_id].nil?}.each do |option_type|
            sku_prop_ids.delete(option_type[:sku_prop_id])
        end

        raise StandardError.new("Invalid SKU Count") if sku_prop_ids.size > 1

        product_data[:option_types].select {|option_type| option_type[:sku_prop_id].nil?}.each do |option_type|
            option_type[:sku_prop_id] = sku_prop_ids.shift
        end

        product_data[:option_types].each do |option_type|
            combinations = []

            option_type[:values].each do |option_value|
                combinations << "#{option_type[:sku_prop_id]}:#{option_value[:sku_id]}"
            end

            option_type[:combinations] = combinations
        end

        sku_attr_id_base = nil
        product_data[:option_types].each do |option_type|
            all_searches = []

            sku_properties.each do |sku_property|
                sku_attr_ids = sku_property[:attr].split(';')

                sku_attr_ids.select {|sku_attr_id| sku_attr_id.split(':')[0] == option_type[:sku_prop_id]}.each do |sku_attr_id|
                    sku_attr_id_base = sku_attr_id
                    break
                end
            end

            sku_properties.each do |sku_property_search|
                sku_property_search_ids = sku_property_search[:attr].split(';')

                if sku_property_search_ids.include?(sku_attr_id_base)
                    sku_price = sku_property_search[:price]

                    other_sku_attr_ids = sku_property_search_ids
                    other_sku_attr_ids.delete(sku_attr_id_base)

                    all_searches << {
                        base: sku_attr_id_base,
                        price: sku_price,
                        others: other_sku_attr_ids,
                    }
                end
            end

            all_searches.each do |search|
                sku_attr_id_base = search[:base]
                sku_price = search[:price]
                other_sku_attr_ids = search[:others]

                option_type[:combinations].each do |combination|
                    sku_properties.each do |sku_property|
                        check = true
                        other_sku_attr_ids.each do |other_sku_attr_id|
                            if !sku_property[:attr].split(';').include?(other_sku_attr_id)
                                check = false
                                break
                            end
                        end

                        if !sku_property[:attr].split(';').include?(combination)
                            check = false
                        end

                        if check
                            if sku_property[:price] != sku_price
                                option_type[:price_changed] = true
                            end
                        end

                        break if option_type[:price_changed]
                    end
                end
            end

            product_data[:count_price_modifiers] += 1 if option_type[:price_changed]
        end

        if product_data[:has_sku] && product_data[:count_price_modifiers] == 1
            product_data[:price] = product_data[:min_price]

            product_data[:option_types].each do |option_type|
                option_type[:values].each do |option_value|
                    if option_type[:price_changed]
                        sku_attr = "#{option_type[:sku_prop_id]}:#{option_value[:sku_id]}"
                        sku_properties.select {|sku_property| sku_property[:attr].split(';').include?(sku_attr)}.each do |sku_property|
                            option_value[:price] = sku_property[:price].to_f - product_data[:price].to_f
                            break
                        end
                    else
                        option_value[:price] = 0.0
                    end
                end
            end
        else
            product_data[:price] = product_data[:max_price]

            product_data[:option_types].each do |option_type|
                option_type[:values].each do |option_value|
                    option_value[:price] = 0.0
                end
            end
        end

        html.css('.product-params').each do |this|
            product_data[:short_description] = this.css('.ui-box-body').first.to_s

            this.css('dl').each do |dl|
                attribute_data = {
                    name: dl.css('dt').first.text.gsub(/\:/, ''),
                    value: dl.css('dd').first.text,
                }

                product_data[:attributes] << attribute_data
            end
        end

        product_data[:country_region_of_manufacture] = html.css('.seller-info .seller address').text.strip

        html.css('.pnl-packaging').each do |this|
            product_data[:unit_type] = this.css('dd').first.text

            product_data[:package_weight] = this.css('dd.pnl-packaging-weight').first.attr('rel')
            product_data[:package_weight_human] = this.css('dd.pnl-packaging-weight').first.text

            product_data[:package_size] = this.css('dd.pnl-packaging-size').first.attr('rel')
            product_data[:package_size_human] = this.css('dd.pnl-packaging-size').first.text
        end

        query_params = {_id: product[:_id]}

        description_url_regex = /window\.runParams\.descUrl\=\"(.*?)\"\;/i
        description_url_matches = description_url_regex.match(html.to_s)

        if description_url_matches && description_url_matches.size == 2
            description_url = description_url_matches[1]

            description_html = Nokogiri::HTML(open(description_url))

            description_regex = /.*window\.productDescription\=\'(.*)\'.*/mi
            description_matches = description_regex.match(description_html.to_s)

            if description_matches && description_matches.size == 2
                product_data[:description] = description_matches[1]
            end

            Nokogiri::HTML.fragment(product_data[:description]).css('img').each do |img|
                product_data[:image_urls] << img.attr('src') if img.attr('src')
            end

            description_html = Nokogiri::HTML.fragment(product_data[:description])
            description_html.css('img').remove
            product_data[:description] = description_html.to_s
        else
            raise StandardError.new("No Description")
        end

        base_name = '/tmp/scraper/aliexpress'
        product_directory = "#{base_name}/images/#{product_data[:aliexpress_id]}"
        product_color_directory = "#{base_name}/images/#{product_data[:aliexpress_id]}/colors"

        FileUtils::mkdir_p product_directory
        FileUtils::mkdir_p product_color_directory

        image_threads = []
        i = 1
        product_data[:image_urls].each do |image_url|
            filename = "/images/#{product_data[:aliexpress_id]}/#{i}.jpg"

            # image_threads << Thread.new do
                begin
                    open(URI.encode(image_url)) do |f|
                        File.open(base_name + filename, 'wb') do |file|
                            file.puts f.read
                        end
                    end

                    product_data[:images] << 'media/import' + filename
                rescue StandardError => e
                    puts "Image download error: #{image_url} (#{e.message})".red
                end
            # end

            i += 1
        end

        product_data[:option_types].select {|option_type| option_type[:type] == 'color'}.each do |option_type|
            option_type[:values].each do |color|
                if color[:url]
                    filename = "/images/#{product_data[:aliexpress_id]}/colors/#{color[:title].gsub(/\W/, '-')}.jpg"

                    # image_threads << Thread.new do
                        begin
                            open(URI.encode(color[:url])) do |f|
                                File.open(base_name + filename, 'wb') do |file|
                                    file.puts f.read
                                end
                            end

                            fn = 'media/import' + filename
                            color[:image] = fn
                            product_data[:images] << fn
                        rescue StandardError => e
                            puts "Color download error: #{color[:url]} (#{e.message})".red
                            color[:image] = color[:title]
                        end
                    # end
                else
                    color[:image] = color[:title]
                end

                if color[:thumb_url]
                    filename = "/images/#{product_data[:aliexpress_id]}/colors/#{color[:title].gsub(/\W/, '-')}_thumb.jpg"

                    # image_threads << Thread.new do
                        begin
                            open(URI.encode(color[:thumb_url])) do |f|
                                File.open(base_name + filename, 'wb') do |file|
                                    file.puts f.read
                                end
                            end

                            color[:value] = 'media/import' + filename
                        rescue StandardError => e
                            puts "Color thumbnail download error: #{color[:thumb_url]} (#{e.message})".red
                        end
                    # end
                end
            end
        end
        image_threads.each(&:join)

        product = Database.update_product(product[:_id], product_data)

        puts "[#{category[:name]}] #{product[:aliexpress_id]}. #{remaining} remaining".green
    end

    def self.get_max_price(url)
        max_price_url = if url.include?('SortType=')
            url.gsub(/SortType=(.*)&+/, '') + '&SortType=price_desc'
        else
            url + (url.include?('?') ? '&' : '?') + 'SortType=price_desc'
        end

        html = Nokogiri::HTML(open(max_price_url))

        price = html.css('#list-items ul li').first.css('.price .value[itemprop=price]').text
        if PRICE_AS_BRL
            price.gsub(/[^\d,]/, '').gsub(/,/, '.').to_f
        else
            price.gsub(/[^\d\.]/, '').to_f
        end
    end

    def self.get_min_price(url)
        min_price_url = if url.include?('SortType=')
            url.gsub(/SortType=(.*)&+/, '') + '&SortType=price_asc'
        else
            url + (url.include?('?') ? '&' : '?') + 'SortType=price_asc'
        end

        html = Nokogiri::HTML(open(min_price_url))

        price = html.css('#list-items ul li').first.css('.price .value[itemprop=price]').text
        if PRICE_AS_BRL
            price.gsub(/[^\d,]/, '').gsub(/,/, '.').to_f
        else
            price.gsub(/[^\d\.]/, '').to_f
        end
    end

    def self.set_params(url)
        params = {
            'shipCountry' => 'US', # Ship to USA
            'isFreeShip' => 'y', # Free Shipping
            'isFavorite' => 'n',
            'isRtl' => 'yes', # 1 Piece Only
            'isOnSale' => 'n',
            'isBigSale' => 'n',
            'similar_style' => 'n',
            'isAtmOnline' => 'n',
            'g' => 'y',
            'needQuery' => 'n',
        }

        params.each do |k, v|
            url = if url.include?("#{k}=")
                url.gsub(%r(#{k}=(.*)&+), '') + "&#{k}=#{v}"
            else
                url + (url.include?('?') ? '&' : '?') + "#{k}=#{v}"
            end
        end

        return url
    end
end
