# export MONGO_URL=mongodb://stark:passtrash123@ds063892.mongolab.com:63892/general

util = Meteor.npmRequire('util')
async = Meteor.npmRequire('async')

if Meteor.isServer
    Meteor.startup ->
        console.log "START"

        # product_url = 'http://www.aliexpress.com/item/Free-Shipping-Women-Bodycon-Sexy-Vogue-Casual-Fit-Splicing-Backless-V-Neck-Two-Piece-Beach-Bath/32332332387.html'
        category_url = 'http://www.aliexpress.com/category/200000784/swimwear.html'

        Scraper.scrape_category category_url, (category) ->
            # console.log util.inspect(category, false, null)

            products = Products.find({category_id: category._id, scraped: false}).fetch()

            console.log "Going to scrape #{products.length} products"

            async.eachLimit products, 50, Meteor.bindEnvironment((product, async_products_callback) ->
                Scraper.scrape_product product, (error, product) ->
                    if not error
                        console.log "#{product['title']} [Done]"
                    # if
                    async_products_callback()
                # scrape_product
            ), (error) ->
                throw error if error

                console.log "Done"
            # each
        # scrape_category
    # startup
# isServer
