request = Meteor.npmRequire('request')#.defaults({'proxy': 'http://167.114.174.182:3128'})
cheerio = Meteor.npmRequire('cheerio')
util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')
moment = Meteor.npmRequire('moment')

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
            headers: {
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Cache-Control': 'max-age=0',
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_4) AppleWebKit/600.7.12 (KHTML, like Gecko) Version/8.0.7 Safari/600.7.12'
            }
        }
    # build_options

    @scrape_category: (category_url, callback) ->
        query_params = {url: category_url}
        Categories.update(query_params, query_params, {upsert: true})
        category = Categories.findOne(query_params)

        console.log "Scraping category ##{category._id}"

        Scraper.scrape_category_page category_url, 1, category._id, (total_pages) ->
            console.log "Total of pages: #{total_pages}"

            callback(category)
        # scrape_category_page
    # scrape_category

    @scrape_category_page: (category_page_url, page_number, category_id, callback) ->
        console.log "Scraping page ##{page_number} (#{category_page_url})"

        # request = Meteor.npmRequire('request').defaults({'proxy': Scraper.proxy()})

        request Scraper.build_options(category_page_url), Meteor.bindEnvironment (error, response, html) ->
            throw error if error

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

            product_ids = Products.batchInsert(products)

            last_page = false
            $('span.page-end.ui-pagination-next.ui-pagination-disabled').filter ->
                last_page = true
            # page-end

            if last_page or page_number >= 10
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
            throw error if error

            $ = cheerio.load(html)

            product_data = {
                aliexpress_id: product['aliexpress_id'],
                category_id: product['category_id'],
                url: product['url'],
                scraped: true
            }

            $('h1.product-name[itemprop=name]').filter ->
                product_data['title'] = $(this).text()
            # product-name

            query_params = {_id: product['_id']}

            Products.update(query_params, product_data, {upsert: false})
            product = Products.findOne(query_params)

            callback(product)
        # request
    # scrape_product
# Scraping
