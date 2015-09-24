require 'csv'
require 'fileutils'
require 'colorize'

require './lib/database.rb'

class Exporter
  def self.export_search_url(url)
    category = Database.get_category(url)
    products = Database.get_products_to_export(category[:_id])

    filename = "/tmp/scraper/aliexpress/#{category[:name]}.csv"

    puts "[#{category[:name]}] Exporting #{products.count.to_i} products to #{filename}".yellow

    FileUtils::mkdir_p '/tmp/scraper/aliexpress'

    CSV.open(filename, 'w', col_sep: CSV_DELIMITER) do |csv|
      csv << ['sku','_store','_attribute_set','_type','_category','_root_category','_product_websites','color','style','condition','model','seller_name','product_url','brand','currency_price','cost','country_of_manufacture','created_at','custom_design','custom_design_from','custom_design_to','custom_layout_update','description','gallery','gift_message_available','has_options','image','image_label','manufacturer','media_gallery','meta_description','meta_keyword','meta_title','minimal_price','msrp','msrp_display_actual_price_type','msrp_enabled','name','news_from_date','news_to_date','options_container','page_layout','price','required_options','short_description','small_image','small_image_label','special_from_date','special_price','special_to_date','status','tax_class_id','thumbnail','thumbnail_label','updated_at','url_key','url_path','visibility','weight','unit_type', 'package_size','qty','min_qty','use_config_min_qty','is_qty_decimal','backorders','use_config_backorders','min_sale_qty','use_config_min_sale_qty','max_sale_qty','use_config_max_sale_qty','is_in_stock','notify_stock_qty','use_config_notify_stock_qty','manage_stock','use_config_manage_stock','stock_status_changed_auto','use_config_qty_increments','qty_increments','use_config_enable_qty_inc','enable_qty_increments','is_decimal_divided','_links_related_sku','_links_related_position','_links_crosssell_sku','_links_crosssell_position','_links_upsell_sku','_links_upsell_position','_associated_sku','_associated_default_qty','_associated_position','_tier_price_website','_tier_price_customer_group','_tier_price_qty','_tier_price_price','_group_price_website','_group_price_customer_group','_group_price_price','_media_attribute_id','_media_image','_media_lable','_media_position','_media_is_disabled','_custom_option_store','_custom_option_type','_custom_option_title','_custom_option_is_required','_custom_option_price','_custom_option_sku','_custom_option_max_characters','_custom_option_sort_order','_custom_option_row_title','_custom_option_row_price','_custom_option_row_sku','_custom_option_row_sort', 'thumb_options']

      products.each do |product|
        tmp_images = []
        product[:images].each do |image|
          tmp_images << image
        end

        tmp_variations = []
        product[:option_types].each do |option_type|
          option_values = option_type[:values]
          i = 0

          if option_values.size > 0
            option_value = option_values.shift
            tmp_variations << ['drop_down', option_type[:title], 1, nil, nil, nil, 0, option_value[:title], option_value[:price], "#{product[:aliexpress_id]}-#{option_type[:title]}-#{option_value[:title]}", i, option_value[:value]]

            i += 1
            option_values.each do |option_value|
              ov = option_values.shift
              tmp_variations << [nil, nil, 1, nil, nil, nil, 0, ov[:title], ov[:price], "#{product[:aliexpress_id]}-#{option_type[:title]}-#{ov[:title]}", i, ov[:value]]
              i += 1
            end
          end
        end

        if tmp_variations.size == 0
          tmp_variations = [Array.new(12)]
        end

        last_category = nil
        categories = ['']
        default_categories = ['Default Category']
        product[:category].each do |category_name|
          if last_category
            last_category = last_category + '/' + category_name
          else
            last_category = category_name
          end

          categories << last_category
          default_categories << 'Default Category'
        end

        attribute_color = nil
        attribute_style = nil
        # TODO need to scrape item condition
        attribute_condition = nil
        attribute_model = nil
        attribute_brand = nil

        product[:attributes].each do |attribute|
          case attribute[:name].downcase
          when 'color'
            attribute_color = attribute[:value]
          when 'style'
            attribute_style = attribute[:value]
          when 'model'
            attribute_model = attribute[:value]
          when 'brand'
            attribute_brand = attribute[:value]
          end
        end

        product_images = product[:images]

        tmp_variation = tmp_variations.shift
        rows = [[product[:aliexpress_id],nil,'Default','simple',categories.shift,default_categories.shift,'base',attribute_color,attribute_style,attribute_condition,attribute_model,product[:seller_name],product[:url],attribute_brand,nil,nil,product[:country_region_of_manufacture],nil,nil,nil,nil,nil,product[:description],nil,nil,1,tmp_images.shift,nil,nil,nil,nil,nil,nil,nil,product[:price],'Use config','Use config',product[:title],nil,nil,'Product Info Column',nil,product[:price].to_f + (product[:price].to_f * PRICE_MULTIPLIER),1,product[:short_description],tmp_images.shift,nil,nil,nil,nil,1,2,tmp_images.shift,nil,nil,nil,nil,4,product[:package_weight],product[:unit_type],product[:package_size_human],100,0,1,0,0,1,1,1,0,1,1,nil,1,0,1,0,1,0,1,0,0,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,88,product_images.shift,nil,1,0,nil,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10],tmp_variation[11]]]

        i = 2
        product_images.each do |image|
          tmp_variation = tmp_variations.shift

          unless tmp_variation
            tmp_variation = Array.new(11)
          end

          rows << [nil,nil,nil,nil,categories.shift,default_categories.shift,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,image,nil,i,0,nil,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10],tmp_variation[11]]

          i += 1
        end

        tmp_variations.each do |tmp_variation|
           rows << [nil,nil,nil,nil,categories.shift,default_categories.shift,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10],tmp_variation[11]]
        end

        categories.each do |category|
          rows << [nil,nil,nil,nil,category,default_categories.shift,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,tmp_variation[0],tmp_variation[1],tmp_variation[2],tmp_variation[3],tmp_variation[4],tmp_variation[5],tmp_variation[6],tmp_variation[7],tmp_variation[8],tmp_variation[9],tmp_variation[10],tmp_variation[11]]
        end

        rows.each do |row|
          csv << row
        end
      end
    end

    puts "Exported".green
  end
end