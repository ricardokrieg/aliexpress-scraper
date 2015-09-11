request = Meteor.npmRequire('request')#.defaults({'proxy': 'http://167.114.174.182:3128'})
cheerio = Meteor.npmRequire('cheerio')
util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')
moment = Meteor.npmRequire('moment')
fs = Meteor.npmRequire('graceful-fs')
mkdirp = Meteor.npmRequire('mkdirp')

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

        Scraper.scrape_category_page category_url, 1, category._id, (total_pages) ->
            console.log "Total of pages: #{total_pages}"

            callback(category)
        # scrape_category_page
    # scrape_category

    @scrape_category_page: (category_page_url, page_number, category_id, callback) ->
        console.log "Scraping page ##{page_number} (#{category_page_url})"

        # request = Meteor.npmRequire('request').defaults({'proxy': Scraper.proxy()})

        request Scraper.build_options(category_page_url), Meteor.bindEnvironment (error, response, html) ->
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

            if last_page# or page_number >= 2
                callback(page_number)
            else
                $('a.page-next.ui-pagination-next').filter ->
                    Scraper.scrape_category_page($(this).attr('href'), page_number+1, category_id, callback)
                # page-next
            # if
        # request
    # scrape_category_page

    @scrape_product: (product, callback) ->
        request Scraper.build_options(product['url']), Meteor.bindEnvironment (error, response, html) ->
            if error
                console.log "#{product['aliexpress_id']} [Error]"
                callback(error, null)
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
                colors: [],
                sizes: [],
                attributes: []
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

            price_regex = /.*window\.runParams\.maxPrice=\"(.*)\".*/i
            price_matches = price_regex.exec(html)
            if price_matches and price_matches.length == 2
                product_data['price'] = price_matches[1].toCurrency()
            else
                console.log "#{product['aliexpress_id']} [Error][price]"
                callback(new Error("Could not get price", null))
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

            # TODO Should check if item is available
            # var skuProducts=[{"skuAttr":"14:173#blue;5:100014064","skuPropIds":"173,100014064","skuVal":{"actSkuCalPrice":"8.50","actSkuMultiCurrencyCalPrice":"33.43","actSkuMultiCurrencyDisplayPrice":"33,43","actSkuMultiCurrencyPrice":"R$ 33,43","actSkuPrice":"8.50","availQuantity":19,"inventory":20,"isActivity":true,"skuCalPrice":"10.63","skuMultiCurrencyCalPrice":"41.81","skuMultiCurrencyDisplayPrice":"41,81","skuMultiCurrencyPrice":"R$ 41,81","skuPrice":"10.63"}}
            $('#product-info-sku').filter ->
                $(this).children('dl.product-info-color').find('li a').filter ->
                    color_data = {
                        title: $(this).attr('title'),
                        thumb_url: $(this).children().first().attr('src')
                    }
                    product_data['colors'].push(color_data)
                # product-info-color

                $(this).children('dl.product-info-size').find('li a').filter ->
                    product_data['sizes'].push($(this).text())
                # product-info-size
            # product-info-sku

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

                request Scraper.build_options(description_url), Meteor.bindEnvironment (error, response, html) ->
                    if error
                        console.log "#{product['aliexpress_id']} [Error][description]"
                        callback(error, null)
                        return
                    # if

                    description_regex = /.*window\.productDescription\=\'(.*)\'.*/i
                    description_matches = description_regex.exec(html)

                    if description_matches and description_matches.length == 2
                        product_data['description'] = description_matches[1]
                    # if

                    ############################################################
                    # TODO remove this
                    # product_data['description'] = product_data['description'][0..100] + ' ...'
                    # product_data['short_description'] = product_data['short_description'][0..100] + ' ...'
                    ############################################################

                    Scraper.download_product_images product_data, Meteor.bindEnvironment (product_data) ->
                        Products.update(query_params, product_data, {upsert: false})
                        product = Products.findOne(query_params)

                        callback(null, product)
                    # download_product_images
                # request
            else
                callback(new Error("No Description"), null)
            # if
        # request
    # scrape_product

    @download_product_images: (product_data, callback) ->
        base_name = '/tmp/scraper/aliexpress'
        product_directory = "#{base_name}/images/#{product_data['aliexpress_id']}"
        product_color_directory = "#{base_name}/images/#{product_data['aliexpress_id']}/colors"

        mkdirp product_directory, (error) ->
            throw error if error

            i = 1
            for image_url in product_data['image_urls']
                filename = "/images/#{product_data['aliexpress_id']}/#{i}.jpg"

                image_request = request(image_url).pipe(fs.createWriteStream(base_name + filename))
                image_request.on 'error', (error) ->
                    console.log("Image download error: #{image_url}")
                    console.log(error)
                # error

                product_data['images'].push('media/import' + filename)

                i += 1
            # for

            mkdirp product_color_directory, (error) ->
                throw error if error

                for color in product_data['colors']
                    if color['thumb_url']
                        filename = "/images/#{product_data['aliexpress_id']}/colors/#{color['title']}.jpg"

                        image_request = request(color['thumb_url']).pipe(fs.createWriteStream(base_name + filename))
                        image_request.on 'error', (error) ->
                            console.log("Thumbnail download error: #{color['thumb_url']}")
                            console.log(error)
                        # error

                        color['image'] = 'media/import' + filename
                    else
                        color['image'] = color['title']
                    # if
                # for

                callback(product_data)
            # mkdirp
        # mkdirp
    # download_product_images
# Scraping
