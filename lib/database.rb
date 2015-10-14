require 'mongo'

class Database
  def self.client
    if @client
      @client
    else
      Mongo::Logger.logger.level = ::Logger::FATAL
      @client = Mongo::Client.new(['localhost:27017'], database: 'aliexpress-scraper')

      @client['categories'].indexes.create_one({url: 1}, {unique: true, dropDups: true})
      @client['products'].indexes.create_one({aliexpress_id: 1}, {unique: true, dropDups: true})

      @client
    end
  end

  def self.categories
    self.client['categories']
  end

  def self.products
    self.client['products']
  end

  def self.get_category(url)
    category_name = /^.*\/(.*)\.html.*$/i.match(url)[1]

    self.save_category(category_name, url)
  end

  def self.save_category(name, url)
    begin
      self.categories.insert_one(name: name, url: url)
    rescue Mongo::Error::OperationFailure
    end

    self.categories.find(url: url).limit(1).first
  end

  def self.insert_products(products, category)
    products_before = self.products.find(category_id: category[:_id]).count

    if products.size > 0
      begin
        self.products.insert_many(products).n
      rescue Mongo::Error::OperationFailure
      end
    end

    self.products.find(category_id: category[:_id]).count - products_before
  end

  def self.update_product(product_id, product_data)
    self.products.find(_id: product_id).replace_one(product_data)

    self.products.find(_id: product_id).limit(1).first
  end

  def self.get_products_to_scrape(category_id)
    self.products.find(category_id: category_id, scraped: false)
  end

  def self.get_products_to_export(category_id)
    self.products.find(category_id: category_id, scraped: true)
  end
end
