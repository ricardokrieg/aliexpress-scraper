request = Meteor.npmRequire('request')#.defaults({'proxy': 'http://167.114.174.182:3128'})
cheerio = Meteor.npmRequire('cheerio')
util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')
moment = Meteor.npmRequire('moment')
fs = Meteor.npmRequire('graceful-fs')
mkdirp = Meteor.npmRequire('mkdirp')
chalk = Meteor.npmRequire('chalk')

chalk.enabled = true

class @Scraper
    @proxy: ->
        proxies = ['http://24.205.244.90:7004',
        'http://23.246.227.198:80',
        'http://54.171.113.162:80',
        'http://152.179.42.178:3128',
        'http://167.114.113.4:80',
        'http://167.114.174.182:3128',
        'http://198.89.126.203:80',
        'http://143.95.62.16:80',
        'http://54.153.121.150:8080',
        'http://173.22.98.89:80',
        'http://158.69.128.63:3128',
        'http://206.123.214.4:443',
        'http://208.111.40.160:80',
        'http://152.8.244.29:8080',
        'http://173.201.177.140:80',
        'http://167.114.67.197:80',
        'http://54.148.167.203:80',
        'http://216.172.191.226:80',
        'http://64.62.233.67:80']

        proxies[Math.floor(Math.random() * proxies.length)]
    # proxy

    @build_options: (url) ->
        options = {
            url: url,
            timeout: 120000,
            headers: {
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Cache-Control': 'max-age=0',
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/600.7.12 (KHTML, like Gecko) Version/8.0.7 Safari/600.7.12'
            }
        }
    # build_options

    @scrape_category: (category_url, callback) ->
        category_name = /^.*\/(.*)\.html.*$/i.exec(category_url)

        query_params = {url: category_url}
        update_params = {url: category_url, name: category_name[1]}

        Categories.update(query_params, update_params, {upsert: true})
        category = Categories.findOne(query_params)

        console.log "Scraping category ##{category.name}"

        Scraper.scrape_category_page category_url, 1, category._id, (err, total_pages) ->
            if err
                callback(err, null)
                return
            # if

            console.log "Total of pages: #{total_pages}"

            callback(null, category)
        # scrape_category_page
    # scrape_category

    @scrape_category_page: (category_page_url, page_number, category_id, callback) ->
        console.log "Scraping page ##{page_number} (#{category_page_url})"

        # request = Meteor.npmRequire('request').defaults({'proxy': Scraper.proxy()})

        category_request = request Scraper.build_options(category_page_url), Meteor.bindEnvironment (err, response, html) ->
            if err
                callback(err, null)
                return
            # if

            $ = cheerio.load(html)

            products = []
            $('li.list-item').filter ->
                aliexpress_id = $(this).find('input.atc-product-id[type=hidden]').attr('value')
                product_url = $(this).find('a.product').attr('href')

                product_data = {
                    aliexpress_id: aliexpress_id,
                    category_id: category_id,
                    url: product_url,
                    scraped: false
                }

                products.push(product_data)
            # list-item

            duplicate_product_ids = (p['aliexpress_id'] for p in Products.find().fetch())

            products = products.filter (product) -> product['aliexpress_id'] not in duplicate_product_ids

            Products.batchInsert(products) if products.length > 0
            console.log "Added #{products.length} products"

            last_page = false
            $('span.page-end.ui-pagination-next.ui-pagination-disabled').filter ->
                last_page = true
            # page-end

            if last_page or (Meteor.PAGE_LIMIT >= 0 and page_number >= Meteor.PAGE_LIMIT)
                callback(null, page_number)
            else
                $('a.page-next.ui-pagination-next').filter ->
                    Scraper.scrape_category_page($(this).attr('href'), page_number+1, category_id, callback)
                # page-next
            # if
        # request

        category_request.on 'error', (err) ->
            console.log chalk.red("Category Request Error: #{err.message}")
            # callback(err, null)
            return
        # error
    # scrape_category_page

    @scrape_product: (product, callback) ->
        product_request = request Scraper.build_options(product['url']), Meteor.bindEnvironment (err, response, html) ->
            if err
                callback(err, product)
                return
            # if

            $ = cheerio.load(html)

            product_data = {
                aliexpress_id: product['aliexpress_id'],
                category_id: product['category_id'],
                url: product['url'],
                scraped: true,
                description: null,
                short_description: 'N/A',
                category: [],
                image_urls: [],
                images: [],
                attributes: [],
                option_types: [],
                count_price_modifiers: 0,
                has_sku: true
            }

            $('h1.product-name[itemprop=name]').filter ->
                product_data['title'] = $(this).text()
            # product-name

            $('a.store-lnk').filter ->
                product_data['seller_name'] = $(this).attr('title') unless 'seller_name' of product_data
            # store-lnk

            $('.ui-breadcrumb').filter ->
                $(this).find('a').filter ->
                    product_data['category'].push($(this).text())
                # category tag
            # ui-breadcrumb
            product_data['category'].splice(0, 2)

            # $('span.multi-currency').filter ->
            #     product_data['original_price'] =
            #         $(this).children('[itemprop=priceCurrency]').text().strip() +
            #         ' ' +
            #         $(this).children('#multi-currency-price').text().strip()
            # # multi-currency

            min_price_regex = /.*window\.runParams\.minPrice=\"(.*)\".*/i
            min_price_matches = min_price_regex.exec(html)
            if min_price_matches and min_price_matches.length == 2
                product_data['min_price'] = min_price_matches[1].toCurrency()
            else
                console.log chalk.red("#{product['aliexpress_id']} [Error][min_price]")
                callback(new Error("Could not get price", product))
                return
            # if

            max_price_regex = /.*window\.runParams\.maxPrice=\"(.*)\".*/i
            max_price_matches = max_price_regex.exec(html)
            if max_price_matches and max_price_matches.length == 2
                product_data['max_price'] = max_price_matches[1].toCurrency()
            else
                console.log chalk.red("#{product['aliexpress_id']} [Error][max_price]")
                callback(new Error("Could not get price", product))
                return
            # if

            # $('#sku-price').filter ->
            #     product_data['price'] = $(this).text().strip()

            #     if product_data['price'].indexOf('-') > -1
            #         product_data['price'] = product_data['price'].split(' - ')[1]
            #     # if

            #     product_data['price'] = product_data['price'].toCurrency()
            # # sku-price

            $('ul.image-nav li.image-nav-item span img').filter ->
                image_url = $(this).attr('src').replace /_50x50\..*/, ''
                product_data['image_urls'].push(image_url)
            # image-nav

            if product_data['image_urls'].length == 0
                $('img[data-role=thumb]').filter ->
                    image_url = $(this).attr('src').replace /_350x350\..*/, ''
                    product_data['image_urls'].push(image_url)
                # thumb
            # if

            sku_regex = /var skuProducts=(.*);/i
            sku_matches = sku_regex.exec(html)
            sku_prop_ids = []
            sku_properties = []

            if sku_matches and sku_matches.length == 2
                try
                    if JSON.parse(sku_matches[1])[0]['skuAttr']
                        for sku in JSON.parse(sku_matches[1])
                            sku_attr = []
                            for a in sku['skuAttr'].split(';')
                                temp = []
                                for b in a.split(':')
                                    if b.indexOf('#') != -1
                                        b = b[0..b.indexOf('#')-1]
                                    # if
                                    temp.push(b)
                                # for
                                sku_attr.push(temp.join(':'))
                            # for
                            sku_attr = sku_attr.join(';')

                            sku_properties.push({
                                attr: sku_attr,
                                prop_ids: sku['skuPropIds'],
                                price: sku['skuVal']['skuPrice']
                            })
                        # for

                        product_data['sku_properties'] = sku_properties
                        sku_prop_ids = (attr.split(':')[0] for attr in sku_properties[0]['attr'].split(';'))
                    else
                        product_data['has_sku'] = false
                        sku_properties = []
                        product_data['sku_properties'] = []
                    # if
                catch e
                    callback(new Error("Error in SKU info [#{e.message}]"), product)
                    return
                # try
            else
                product_data['has_sku'] = false
                sku_properties = []
                product_data['sku_properties'] = []
            # if

            # TODO Should check if item is available
            $('#product-info-sku').filter ->
                $(this).children('dl').filter ->
                    attribute_title = $(this).children('dt').text().strip().replace(/\:/g, '')
                    attribute_values = []

                    attribute_type = ''
                    if $(this).find('ul').first().hasClass('sku-color')
                        attribute_type = 'color'
                    else if $(this).find('ul').first().hasClass('sku-checkbox')
                        attribute_type = 'checkbox'
                    else
                        callback(new Error("Invalid option type"), product)
                        return
                    # if

                    sku_prop_id = $(this).find('ul').attr('data-sku-prop-id')

                    $(this).find('li a').filter ->
                        sku_id = /^sku\-\d+\-(.*)$/.exec($(this).attr('id'))[1]

                        if attribute_type == 'color'
                            attribute_values.push({
                                url: $(this).children('img').first().attr('bigpic'),
                                thumb_url: $(this).children('img').first().attr('src'),
                                title: $(this).attr('title'),
                                value: $(this).attr('title'),
                                sku_id: sku_id
                            })
                        else
                            attribute_values.push({
                                value: $(this).text(),
                                title: $(this).text(),
                                sku_id: sku_id
                            })
                        # if
                    # li

                    product_data['option_types'].push({
                        sku_prop_id: sku_prop_id,
                        title: attribute_title,
                        type: attribute_type,
                        price_changed: false,
                        values: attribute_values
                    })
                # dl
            # product-info-sku

            for option_type in product_data['option_types'] when option_type['sku_prop_id']
                sku_prop_ids.splice(sku_prop_ids.indexOf(option_type['sku_prop_id']), 1)
            # for

            if sku_prop_ids.length > 1
                callback(new Error("Invalid SKU Count"), product)
                return
            # if

            for option_type in product_data['option_types'] when not option_type['sku_prop_id']
                option_type['sku_prop_id'] = sku_prop_ids.shift()
            # for

            for option_type in product_data['option_types']
                combinations = []

                for option_value in option_type['values']
                    sku_attr_id = "#{option_type['sku_prop_id']}:#{option_value['sku_id']}"
                    combinations.push(sku_attr_id)
                # for

                option_type['combinations'] = combinations
            # for

            for option_type in product_data['option_types']
                all_searches = []

                for sku_property in sku_properties
                    sku_attr_ids = sku_property['attr'].split(';')
                    # sku_price = sku_property['price']

                    for sku_attr_id in sku_attr_ids when sku_attr_id.split(':')[0] == option_type['sku_prop_id']
                        sku_attr_id_base = sku_attr_id
                        break
                    # for
                # for

                for sku_property_search in sku_properties
                    sku_property_search_ids = sku_property_search['attr'].split(';')

                    if sku_attr_id_base in sku_property_search_ids
                        sku_price = sku_property_search['price']

                        other_sku_attr_ids = sku_property_search_ids
                        other_sku_attr_ids.splice(other_sku_attr_ids.indexOf(sku_attr_id_base), 1)

                        all_searches.push({
                            base: sku_attr_id_base,
                            price: sku_price,
                            others: other_sku_attr_ids
                        })
                    # if
                # for

                for search in all_searches
                    sku_attr_id_base = search['base']
                    sku_price = search['price']
                    other_sku_attr_ids = search['others']

                    for combination in option_type['combinations']
                        for sku_property in sku_properties
                            check = true
                            for other_sku_attr_id in other_sku_attr_ids
                                if other_sku_attr_id not in sku_property['attr'].split(';')
                                    check = false
                                    break
                                # if
                            # for
                            if combination not in sku_property['attr'].split(';')
                                check = false
                            # if

                            if check
                                if sku_property['price'] != sku_price
                                    option_type['price_changed'] = true
                                # if
                            # if

                            break if option_type['price_changed']
                        # for
                    # for
                # for

                product_data['count_price_modifiers'] += 1 if option_type['price_changed']
            # for

            if product_data['has_sku'] and product_data['count_price_modifiers'] == 1
                product_data['price'] = product_data['min_price']

                for option_type in product_data['option_types']
                    for option_value in option_type['values']
                        if option_type['price_changed']
                            sku_attr = "#{option_type['sku_prop_id']}:#{option_value['sku_id']}"
                            for sku_property in sku_properties when sku_attr in sku_property['attr'].split(';')
                                option_value['price'] = (parseFloat(sku_property['price']) - parseFloat(product_data['price'])).toFixed(2)
                                break
                            # for
                        else
                            option_value['price'] = parseFloat(0).toFixed(2)
                        # if
                    # for
                # for
            else
                product_data['price'] = product_data['max_price']

                for option_type in product_data['option_types']
                    for option_value in option_type['values']
                        option_value['price'] = parseFloat(0).toFixed(2)
                    # for
                # for
            # if

            $('.product-params').filter ->
                product_data['short_description'] = $(this).find('.ui-box-body').html()

                $(this).find('dl').filter ->
                    attribute_data = {
                        name: $(this).find('dt').text().replace(/\:/g, ''),
                        value: $(this).find('dd').text()
                    }

                    product_data['attributes'].push(attribute_data)
                # dl
            # product-params

            $('.seller-info .seller address').filter ->
                product_data['country_region_of_manufacture'] = $(this).text().strip()
            # seller-info

            $('.pnl-packaging').filter ->
                product_data['unit_type'] = $(this).find('dd').first().text()

                product_data['package_weight'] = $(this).find('dd.pnl-packaging-weight').attr('rel')
                product_data['package_weight_human'] = $(this).find('dd.pnl-packaging-weight').text()

                product_data['package_size'] = $(this).find('dd.pnl-packaging-size').attr('rel')
                product_data['package_size_human'] = $(this).find('dd.pnl-packaging-size').text()
            # pnl-packaging

            query_params = {_id: product['_id']}

            description_url_regex = /window\.runParams\.descUrl\=\"(.*?)\"\;/i
            description_url_matches = description_url_regex.exec(html)

            if description_url_matches and description_url_matches.length == 2
                description_url = description_url_matches[1]

                description_request = request Scraper.build_options(description_url), Meteor.bindEnvironment (err, response, html) ->
                    if err
                        callback(err, product)
                        return
                    # if

                    description_regex = /.*window\.productDescription\=\'(.*)\'.*/i
                    description_matches = description_regex.exec(html)

                    if description_matches and description_matches.length == 2
                        product_data['description'] = description_matches[1]
                    # if

                    $ = cheerio.load(product_data['description'])
                    $('img').filter ->
                        product_data['image_urls'].push($(this).attr('src')) if $(this).attr('src')
                        $(this).remove()
                    # img

                    product_data['description'] = $.html()

                    ############################################################
                    # TODO remove this
                    # product_data['description'] = product_data['description'][0..100] + ' ...'
                    # product_data['short_description'] = product_data['short_description'][0..100] + ' ...'
                    ############################################################

                    Scraper.download_product_images product_data, Meteor.bindEnvironment (err, product_data) ->
                        if err
                            callback(err, product)
                            return
                        # if

                        Products.update(query_params, product_data, {upsert: false})
                        product = Products.findOne(query_params)

                        callback(null, product)
                        return
                    # download_product_images
                # request

                description_request.on 'error', (err) ->
                    console.log chalk.red("Description Request Error: #{err.message}")
                    # callback(err, product)
                    return
                # error
            else
                callback(new Error("No Description"), product)
                return
            # if
        # request

        product_request.on 'error', (err) ->
            console.log chalk.red("Product Request Error: #{err.message}")
            # callback(err, product)
            return
        # error
    # scrape_product

    @download_product_images: (product_data, callback) ->
        base_name = '/tmp/scraper/aliexpress'
        product_directory = "#{base_name}/images/#{product_data['aliexpress_id']}"
        product_color_directory = "#{base_name}/images/#{product_data['aliexpress_id']}/colors"

        mkdirp product_directory, (err) ->
            if err
                callback(err, null)
                return
            # if

            i = 1
            for image_url in product_data['image_urls']
                filename = "/images/#{product_data['aliexpress_id']}/#{i}.jpg"

                try
                    image_request = request(Scraper.build_options(image_url)).pipe(fs.createWriteStream(base_name + filename))
                    image_request.on 'error', (err) ->
                        console.log chalk.red("Image download error: #{image_url}")
                    # error

                    product_data['images'].push('media/import' + filename)
                catch e
                    console.log chalk.red("Image download error: #{image_url}")
                # try

                i += 1
            # for

            mkdirp product_color_directory, (err) ->
                if err
                    callback(err, null)
                    return
                # if

                # for color in product_data['colors']
                #     if color['thumb_url']
                #         filename = "/images/#{product_data['aliexpress_id']}/colors/#{color['title'].replace(/\W/g, '-')}.jpg"

                #         image_request = request(color['thumb_url']).pipe(fs.createWriteStream(base_name + filename))
                #         image_request.on 'error', (error) ->
                #             console.log("Thumbnail download error: #{color['thumb_url']}")
                #             console.log(error)

                #             color['image'] = color['title']
                #         # error

                #         color['image'] = 'media/import' + filename
                #     else
                #         color['image'] = color['title']
                #     # if
                # # for

                for option_type in product_data['option_types'] when option_type['type'] == 'color'
                    for color in option_type['values']
                        if color['url']
                            filename = "/images/#{product_data['aliexpress_id']}/colors/#{color['title'].replace(/\W/g, '-')}.jpg"

                            try
                                image_request = request(Scraper.build_options(color['url'])).pipe(fs.createWriteStream(base_name + filename))
                                image_request.on 'error', (err) ->
                                    console.log chalk.red("Color download error: #{color['url']}")

                                    color['image'] = color['title']
                                # error

                                color['image'] = 'media/import' + filename
                                product_data['images'].push('media/import' + filename)
                            catch e
                                console.log chalk.red("Color download error: #{color['url']}")

                                color['image'] = color['title']
                            # try
                        else
                            color['image'] = color['title']
                        # if

                        if color['thumb_url']
                            filename = "/images/#{product_data['aliexpress_id']}/colors/#{color['title'].replace(/\W/g, '-')}_thumb.jpg"

                            try
                                image_request = request(Scraper.build_options(color['thumb_url'])).pipe(fs.createWriteStream(base_name + filename))
                                image_request.on 'error', (err) ->
                                    console.log chalk.red("Color thumbnail download error: #{color['thumb_url']}")
                                # error

                                color['value'] = 'media/import' + filename
                            catch e
                                console.log chalk.red("Color thumbnail download error: #{color['thumb_url']}")
                            # try
                        # if
                    # for
                # for

                callback(null, product_data)
            # mkdirp
        # mkdirp
    # download_product_images
# Scraping
