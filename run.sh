bundle install

./local/mongod --smallfiles --dbpath `pwd`/local/db --oplogSize 8 2>&1 > local/mongo.log &
export mongo_id=$!

ruby aliexpress-scraper.rb $1 $2

kill $mongo_id