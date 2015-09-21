# export MONGO_URL=mongodb://stark:passtrash123@ds063892.mongolab.com:63892/general

fs = Meteor.npmRequire('fs')
util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')
chalk = Meteor.npmRequire('chalk')

chalk.enabled = true

# Meteor.CATEGORY_URL = 'http://www.aliexpress.com/category/200000784/swimwear.html'
Meteor.CATEGORY_URL = 'http://www.aliexpress.com/category/200000109/necklaces-pendants.html?shipCountry=US&shipFromCountry=&shipCompanies=&SearchText=&minPrice=&maxPrice=14&minQuantity=&maxQuantity=&isFreeShip=y&isFavorite=n&isRtl=yes&isOnSale=n&isBigSale=n&similar_style=yes&similar_style_id=&isAtmOnline=n&CatId=200000109&g=y&pvId=326-200572191&needQuery=n&isrefine=y'
Meteor.PRICE_MULTIPLIER = 0.3
Meteor.PAGE_LIMIT = 1
Meteor.CSV_DELIMITER = ','

do_export = (category_or_url, callback) ->
    console.log "Exporting"

    category = category_or_url
    if typeof category_or_url is 'string'
        category = Categories.findOne({url: category_or_url})
    # if

    query_params = {category_id: category._id, scraped: true}
    product_ids = Products.find(query_params, {}, {limit: 2}).fetch()

    console.log "Going to export #{product_ids.length} products"

    Exporter.export_products product_ids, category.name, (err) ->
        if err
            console.log chalk.red("Exporter Error: #{err.message}")
        else
            console.log "Done. CSV saved at /tmp/scraper/aliexpress/#{category.name}.csv"
        # if

        callback()
    # export_products
# do_export

do_scrape = (category_url, callback) ->
    Scraper.scrape_category category_url, (err, category) ->
        if err
            console.log chalk.red("Scrape Category Error: #{err.message}")
            return
        # if

        products = Products.find({category_id: category._id, scraped: false}).fetch()

        console.log "Going to scrape #{products.length} products"

        async.eachLimit products, 10, Meteor.bindEnvironment((product, async_products_callback) ->
            Scraper.scrape_product product, (err, product) ->
                if err
                    console.log chalk.red("#{product['aliexpress_id']} [#{err.message}]")
                else
                    console.log "#{product['title']} [Done]"
                # if

                async_products_callback()
            # scrape_product
        ), (err) ->
            if err
                console.log chalk.red("Fatal Error: #{e.message}")
                return
            # if

            console.log "Done"

            do_export(category, callback)
        # each
    # scrape_category
# do_scrape

do_test = (callback) ->
    Categories.remove({})
    Categories.insert({url: 'aliexpress.com', name: 'Testing'})
    category = Categories.findOne()

    Products.remove({})

    product_urls = [
        # This to check if it gets the highest price and ignores the changes in price of >1 options
        # multiple changes
        # all option types:
        # _custom_option_row_price = 0
        # price = maxPrice
        'http://www.aliexpress.com/item/Womens-Elegant-Sleeveless-Bowknot-Patchwork-Office-Lady-Pencil-Wear-to-Work-Business-Casual-Bodycon-Sheath-Dress/32458714518.html?spm=2114.031010208.3.30.aQl6Sl&ws_ab_test=201407_1,201444_6,201409_1',
        'http://www.aliexpress.com/item/2015-New-Summer-Women-s-Sexy-top-Backless-Bowknot-Decoration-round-collar-Solid-Color-Chiffon-Shirt/32372960210.html?spm=2114.031010208.3.181.aQl6Sl&ws_ab_test=201407_1,201444_6,201409_1',

        # this to make sure it gets price changes from the 1 option that price changes
        # only one changes
        # option type that dont change:
        # _custom_option_row_price = 0
        # option type that change:
        # _custom_option_row_price = (option value price) - minPrice
        # price = minPrice
        'http://www.aliexpress.com/item/Classic-14Karat-White-Gold-Wedding-Rings-for-Women-0-6CT-Prong-Setting-Synthetic-Diamond-Engagement-Ring/32447513738.html?ws_ab_test=201407_3,201444_6,201409_2',
        'http://www.aliexpress.com/item/2015-New-Fashion-Vintage-Necklaces-Za-Crystal-Multilayer-Statement-Necklace-Body-Chain-Stone-Choke-Necklaces-PendantsFor/32427059548.html?spm=2114.030010108.3.11.nBgCTL&ws_ab_test=201407_1,201444_6,201409_1',
        'http://www.aliexpress.com/item/Free-shipping-35inch-Super-Long-one-piece-5-clips-in-hair-extensions-amazing-curl-synthetic-hair/1266683115.html?spm=2114.030010108.3.185.6KiSbf&ws_ab_test=201407_1,201444_6,201409_1',

        # no modifiers
        'http://pt.aliexpress.com/item/Fancyinn-Women-One-Piece-Swimsuit-Deep-V-neck-Bacless-Black-and-White-Bathing-Suit-Sexy-Swimwear/32405608652.html?spm=2114.02010108.3.24.vHqmjZ&ws_ab_test=201407_4,201444_6_3_2_1_5_4,201409_3',
        'http://pt.aliexpress.com/item/2015-Sexy-Print-Bikinis-Push-Up-Swimwear-Cheap-Women-Bikinis-Brazilian-push-up-low-waist-Bath/32378414722.html?spm=2114.02010108.3.56.vHqmjZ&ws_ab_test=201407_4,201444_6_3_2_1_5_4,201409_3',
    ]

    for product_url in product_urls
        aliexpress_id = /^.*\/(.*)\.html.*$/.exec(product_url)[1]
        Products.insert({category_id: category._id, scraped: false, url: product_url, aliexpress_id: aliexpress_id})
    # for

    products = Products.find({category_id: category._id, scraped: false}).fetch()

    async.eachLimit products, 10, Meteor.bindEnvironment((product, async_products_callback) ->
        Scraper.scrape_product product, (err, product) ->
            if err
                console.log chalk.red("#{product['title']} [#{err.message}]")
            else
                console.log "#{product['title']} [Done]"
            # if

            async_products_callback()
        # scrape_product
    ), (err) ->
        if err
            console.log chalk.red("Fatal Error: #{e.message}")
            return
        # if

        console.log "Done"

        do_export(category, callback)
    # each
# do_test

if Meteor.isServer
    Meteor.startup ->
        console.log "START"

        try
            stats = fs.lstatSync('../../../../../urls.txt')

            if stats.isFile()
                Meteor.CATEGORY_URL = (url for url in fs.readFileSync('../../../../../urls.txt').toString().split("\n") when url != '')
                console.log "Scraping #{Meteor.CATEGORY_URL.length} urls:"
                console.log Meteor.CATEGORY_URL
            # if
        catch e
        # try

        if typeof Meteor.CATEGORY_URL == 'string'
            Meteor.CATEGORY_URL = [Meteor.CATEGORY_URL]
            console.log "Scraping single url: #{Meteor.CATEGORY_URL}"
        # if

        async.eachSeries Meteor.CATEGORY_URL, Meteor.bindEnvironment((category_url, async_category_url_callback) ->
            console.log "URL: #{category_url}"
            do_scrape(category_url, async_category_url_callback)
            # do_export(category_url, async_category_url_callback)
            # do_test(async_category_url_callback)
        ) # eachSeries
    # startup
# isServer
