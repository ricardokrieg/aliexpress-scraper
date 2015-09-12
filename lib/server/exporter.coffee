async = Meteor.npmRequire('async')
util = Meteor.npmRequire('util')
csv_stringify = Meteor.npmRequire('csv-stringify')
fs = Meteor.npmRequire('fs')
mkdirp = Meteor.npmRequire('mkdirp')

class @Exporter
    @export_products: (product_ids, output_filename, callback) ->
        Exporter.write_header output_filename, Meteor.bindEnvironment ->
            async.eachSeries product_ids, Meteor.bindEnvironment((product_id, async_products_callback) ->
                Exporter.export_product Products.findOne(product_id), (error, rows) ->
                    throw error if error

                    Exporter.save_product rows, output_filename, ->
                        async_products_callback()
                    # save_product
                # export_product
            ), (error) ->
                throw error if error

                console.log "Export Done"

                callback()
            # eachSeries
        # write_header
    # export_products

    @export_product: (product, callback) ->
        tmp_images = []
        for image in product['images']
            tmp_images.push(image)
        # for

        variations = {
            colors: (color['image'] for color in product.colors),
            sizes: product.sizes
        }

        tmp_variations = []
        for option_type of variations
            option_values = variations[option_type]
            i = 0

            if option_values.length > 0
                # TODO scrape variation's SKU
                tmp_variations.push(['drop_down', option_type, 1, null, null, null, 0, option_values.shift(), 0, 'SKU', i])

                i++
                for option_value in option_values
                    # TODO scrape variation's SKU
                    tmp_variations.push([null, null, 1, null, null, null, 0, option_values.shift(), 0, 'SKU', i])
                    i++
                # for
            # if
        # for

        if tmp_variations.length == 0
            tmp_variations = [Array(11)]
        # if

        base_category = ''
        categories = ['']
        for category_name in product.category
            if base_category == ''
                base_category = category_name
            else
                base_category = base_category + '/' + category_name
            # if

            categories.push(base_category)
        # for

        attribute_color = null
        attribute_style = null
        # TODO need to scrape item condition
        attribute_condition = null
        attribute_model = null
        attribute_brand = null

        for attribute in product.attributes
            switch attribute['name']
                when 'Color'
                    attribute_color = attribute['value']
                when 'Style'
                    attribute_style = attribute['value']
                when 'Model'
                    attribute_model = attribute['value']
                when 'Brand'
                    attribute_brand = attribute['value']
            # switch
        # for

        tmp_variation = tmp_variations.shift()
        rows = [[product.aliexpress_id,null,'Default','simple',categories.shift(),'Default Category','base',attribute_color,attribute_style,attribute_condition,attribute_model,product.seller_name,product.url,attribute_brand,null,null,product.country_region_of_manufacture,null,null,null,null,null,product.description,null,null,1,tmp_images.shift(),null,null,null,null,null,null,null,product.price,'Use config','Use config',product.title,null,null,'Product Info Column',null,parseFloat(product.price + (product.price * Meteor.PRICE_MULTIPLIER)).toFixed(2),1,product.short_description,tmp_images.shift(),null,null,null,null,1,2,tmp_images.shift(),null,null,null,null,4,product.package_weight,product.unit_type,product.package_size_human,100,0,1,0,0,1,1,1,0,1,1,null,1,0,1,0,1,0,1,0,0,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,88,product.images.shift(),null,1,0,null,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10]]]

        i = 2
        for image in product.images
            tmp_variation = tmp_variations.shift()

            if not tmp_variation
                tmp_variation = Array(11)
            # if

            rows.push [null,null,null,null,categories.shift(),'Default Category',null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,image,null,i,0,null,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10]]

            i++
        # for

        for tmp_variation in tmp_variations
            rows.push [null,null,null,null,categories.shift(),'Default Category',null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10]]
        # for

        for category in categories
            rows.push [null,null,null,null,category,'Default Category',null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10]]
        # for

        callback(null, rows)
    # export_product

    @save_product: (rows, output_filename, callback) ->
        csv_stringify rows, (error, output) ->
            throw error if error

            fs.appendFile "/tmp/scraper/aliexpress/#{output_filename}.csv", output, (error) ->
                throw error if error

                callback()
            # appendFile
        # csv_stringify
    # save_product

    @write_header: (output_filename, callback) ->
        header = [['sku','_store','_attribute_set','_type','_category','_root_category','_product_websites','color','style','condition','model','seller name','product url','brand','currency price','cost','country_of_manufacture','created_at','custom_design','custom_design_from','custom_design_to','custom_layout_update','description','gallery','gift_message_available','has_options','image','image_label','manufacturer','media_gallery','meta_description','meta_keyword','meta_title','minimal_price','msrp','msrp_display_actual_price_type','msrp_enabled','name','news_from_date','news_to_date','options_container','page_layout','price','required_options','short_description','small_image','small_image_label','special_from_date','special_price','special_to_date','status','tax_class_id','thumbnail','thumbnail_label','updated_at','url_key','url_path','visibility','weight','unit_type', 'package_size','qty','min_qty','use_config_min_qty','is_qty_decimal','backorders','use_config_backorders','min_sale_qty','use_config_min_sale_qty','max_sale_qty','use_config_max_sale_qty','is_in_stock','notify_stock_qty','use_config_notify_stock_qty','manage_stock','use_config_manage_stock','stock_status_changed_auto','use_config_qty_increments','qty_increments','use_config_enable_qty_inc','enable_qty_increments','is_decimal_divided','_links_related_sku','_links_related_position','_links_crosssell_sku','_links_crosssell_position','_links_upsell_sku','_links_upsell_position','_associated_sku','_associated_default_qty','_associated_position','_tier_price_website','_tier_price_customer_group','_tier_price_qty','_tier_price_price','_group_price_website','_group_price_customer_group','_group_price_price','_media_attribute_id','_media_image','_media_lable','_media_position','_media_is_disabled','_custom_option_store','_custom_option_type','_custom_option_title','_custom_option_is_required','_custom_option_price','_custom_option_sku','_custom_option_max_characters','_custom_option_sort_order','_custom_option_row_title','_custom_option_row_price','_custom_option_row_sku','_custom_option_row_sort']]

        csv_stringify header, (error, output) ->
            throw error if error

            mkdirp '/tmp/scraper/aliexpress', (error) ->
                throw error if error

                fs.writeFile "/tmp/scraper/aliexpress/#{output_filename}.csv", output, (error) ->
                    throw error if error

                    callback()
                # writeFile
            # mkdirp
        # csv_stringify
    # write_header
# Exporter
