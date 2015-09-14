# export MONGO_URL=mongodb://stark:passtrash123@ds063892.mongolab.com:63892/general

util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')

Meteor.CATEGORY_URL = 'http://www.aliexpress.com/category/200000784/swimwear.html'
Meteor.PRICE_MULTIPLIER = 0.3
Meteor.PAGE_LIMIT = 1
Meteor.CSV_DELIMITER = ';'

do_export = (category_or_url) ->
    console.log "Exporting"

    category = category_or_url
    if typeof category_or_url is 'string'
        category = Categories.findOne({url: category_or_url})
    # if

    query_params = {category_id: category._id, scraped: true}
    product_ids = Products.find(query_params).fetch()

    console.log "Going to export #{product_ids.length} products"

    Exporter.export_products product_ids, category.name, ->
        console.log "Done"
    # export_products
# do_export

do_scrape = (category_url) ->
    Scraper.scrape_category category_url, (category) ->
        products = Products.find({category_id: category._id, scraped: false}).fetch()

        console.log "Going to scrape #{products.length} products"

        async.eachLimit products, 10, Meteor.bindEnvironment((product, async_products_callback) ->
            try
                Scraper.scrape_product product, (error, product) ->
                    console.log "#{product['title']} [Done]" unless error

                    async_products_callback()
                # scrape_product
            catch e
                console.log "#{product['aliexpress_id']} [Error][#{e.message}]"

                async_products_callback()
            # try
        ), (error) ->
            throw error if error

            console.log "Done"

            do_export(category)
        # each
    # scrape_category
# do_scrape

do_test = ->
    Categories.remove({})
    Categories.insert({url: 'aliexpress.com', name: 'Testing'})
    category = Categories.findOne()

    Products.remove({})

    product_urls = [
        # This to check if it gets the highest price and ignores the changes in price of >1 options
        'http://www.aliexpress.com/item/Womens-Elegant-Sleeveless-Bowknot-Patchwork-Office-Lady-Pencil-Wear-to-Work-Business-Casual-Bodycon-Sheath-Dress/32458714518.html?spm=2114.031010208.3.30.aQl6Sl&ws_ab_test=201407_1,201444_6,201409_1',
        'http://www.aliexpress.com/item/2015-New-Summer-Women-s-Sexy-top-Backless-Bowknot-Decoration-round-collar-Solid-Color-Chiffon-Shirt/32372960210.html?spm=2114.031010208.3.181.aQl6Sl&ws_ab_test=201407_1,201444_6,201409_1',

        # this to make sure it gets price changes from the 1 option that price changes
        'http://www.aliexpress.com/item/Classic-14Karat-White-Gold-Wedding-Rings-for-Women-0-6CT-Prong-Setting-Synthetic-Diamond-Engagement-Ring/32447513738.html?ws_ab_test=201407_3,201444_6,201409_2',
        'http://www.aliexpress.com/item/2015-New-Fashion-Vintage-Necklaces-Za-Crystal-Multilayer-Statement-Necklace-Body-Chain-Stone-Choke-Necklaces-PendantsFor/32427059548.html?spm=2114.030010108.3.11.nBgCTL&ws_ab_test=201407_1,201444_6,201409_1',
        'http://www.aliexpress.com/item/Free-shipping-35inch-Super-Long-one-piece-5-clips-in-hair-extensions-amazing-curl-synthetic-hair/1266683115.html?spm=2114.030010108.3.185.6KiSbf&ws_ab_test=201407_1,201444_6,201409_1'
    ]

    for product_url in product_urls
        aliexpress_id = /^.*\/(.*)\.html.*$/.exec(product_url)[1]
        Products.insert({category_id: category._id, scraped: false, url: product_url, aliexpress_id: aliexpress_id})
    # for

    products = Products.find({category_id: category._id, scraped: false}).fetch()

    async.eachLimit products, 10, Meteor.bindEnvironment((product, async_products_callback) ->
        try
            Scraper.scrape_product product, (error, product) ->
                console.log "#{product['title']} [Done]" unless error

                async_products_callback()
            # scrape_product
        catch e
            console.log "#{product['aliexpress_id']} [Error][#{e.message}]"

            async_products_callback()
        # try
    ), (error) ->
        throw error if error

        console.log "Done"

        do_export(category)
    # each
# do_test

if Meteor.isServer
    Meteor.startup ->
        console.log "START"

        # do_scrape(Meteor.CATEGORY_URL)
        # do_export(Meteor.CATEGORY_URL)
        do_test()
    # startup
# isServer
