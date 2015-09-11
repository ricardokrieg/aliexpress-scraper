# export MONGO_URL=mongodb://stark:passtrash123@ds063892.mongolab.com:63892/general

util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')

Meteor.CATEGORY_URL = 'http://www.aliexpress.com/category/200000784/swimwear.html'
Meteor.PRICE_MULTIPLIER = 0.3
Meteor.PAGE_LIMIT = -1

do_export = (category) ->
    console.log "Exporting"

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
            Scraper.scrape_product product, (error, product) ->
                console.log "#{product['title']} [Done]" unless error

                async_products_callback()
            # scrape_product
        ), (error) ->
            throw error if error

            console.log "Done"

            do_export(category)
        # each
    # scrape_category
# do_scrape

if Meteor.isServer
    Meteor.startup ->
        console.log "START"

        do_scrape(Meteor.CATEGORY_URL)

        # category = Categories.findOne({url: Meteor.CATEGORY_URL})
        # do_export(category)
    # startup
# isServer
