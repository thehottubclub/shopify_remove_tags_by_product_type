require 'json'
require 'httparty'
require 'pry'
require 'shopify_api'
require 'yaml'

@outcomes = {
  errors: [],
  skipped: [],
  skipped_correct_type_didnt_have_tag: [],
  updated_product_tags: [],
  unable_to_save_tags: [],
  unable_to_replace_tags: [],
  responses: []
}

#Load secrets from yaml file & set data values to use
data = YAML.load( File.open( 'config/secrets.yml' ) )
SECURE_URL_BASE = data['url_base']
API_DOMAIN = data['api_domain']

#Constants
DIVIDER = '------------------------------------------'
DELAY_BETWEEN_REQUESTS = 0.11
NET_INTERFACE = HTTParty
STARTPAGE = 1
ENDPAGE = 97
PRODUCT_TYPE_TO_FIND = 'Ski Suits' #Product type to find
TAG_TO_REMOVE = 'bottoms' #Tag to remove

#Script runs w/ 2 args
#Both are strings (product type to find and tag to replace respectively)
#The fallbacks for these are constants above
#Note: Need up update these params to include page range
def main
  if ARGV[0] =~ /\w+/ && ARGV[1] =~ /\w+/
    puts "removing tag #{ARGV[1]} from products based on type: #{ARGV[0]}"
    puts "starting at #{Time.now}"
    # ARGV[0] = Product Type
    # ARGV[1] = Tag To Remove
    do_page_range(ARGV[0], ARGV[1])
  else
    puts "removing tag: #{TAG_TO_REMOVE} from products based on type: #{PRODUCT_TYPE_TO_FIND}"
    puts "starting at #{Time.now}"
    do_page_range(PRODUCT_TYPE_TO_FIND, TAG_TO_REMOVE)
  end

  puts "finished at #{Time.now}"
  puts "finished removing tags from products based on type"

  File.open(filename, 'w') do |file|
    file.write @outcomes.to_json
  end

  @outcomes.each_pair do |k,v|
    puts "#{k}: #{v.size}"
  end
end

def filename
  "data/remove_tags_by_product_type_#{Time.now.strftime("%Y-%m-%d_%k%M%S")}.json"
end

def do_page_range(product_type_to_find, tag_to_remove)
  (STARTPAGE .. ENDPAGE).to_a.each do |current_page|
    do_page(current_page, product_type_to_find, tag_to_remove)
  end
end

def do_page(page_number, product_type_to_find, tag_to_remove)
  puts "Starting page #{page_number}"

  products = get_products(page_number)

  products.each do |product|
    @product_id = product['id']
    do_product(product, product_type_to_find, tag_to_remove)
  end

  puts "Finished page #{page_number}"
end

def get_products(page_number)
  response = secure_get("/products.json?page=#{page_number}")

  JSON.parse(response.body)['products']
end

def do_product(product, product_type_to_find, tag_to_remove)
  begin
    puts DIVIDER
    product_type = product['product_type']
    old_tags = product['tags'].split(', ')

    if( should_skip_based_on_type?(product_type, product_type_to_find) )
      skip(product)
    elsif ( should_skip_based_on_tags?(old_tags, tag_to_remove))
      @outcomes[:skipped_correct_type_didnt_have_tag].push @product_id
      puts "Skipped product #{product['id']} with type #{product['product_type']} because didn't have tag to remove"
    else
      remove_tag_from_product(product, old_tags, tag_to_remove)
    end
  rescue Exception => e
    @outcomes[:errors].push @product_id
    puts "error on product #{product['id']}: #{e.message}"
    puts e.backtrace.join("\n")
    raise e
  end
end

def should_skip_based_on_type?(product_type, product_type_to_find)
  if product_type != product_type_to_find
    return true
  end

  false
end

def should_skip_based_on_tags?(old_tags, tag_to_remove)
  if old_tags.exclude?(tag_to_remove)
    return true
  end

  false
end

def skip(product)
  @outcomes[:skipped].push @product_id
  puts "Skipping product #{product['id']} due to wrong type"
end

def remove_tag_from_product(product, old_tags, tag_to_remove)
  if new_tags = replace_tags(old_tags, tag_to_remove)
    if result = save_tags(product, new_tags)
      @outcomes[:updated_product_tags].push @product_id
      puts "Saved tags for #{product['product_type']} product #{product['id']}: #{product['tags']}"
    else
      @outcomes[:unable_to_save_tags].push @product_id
      puts "Unable to save tags for #{product['id']}:  #{result.body}"
    end
  else
    @outcomes[:unable_to_replace_tags].push @product_id
    puts "unable to replace tags_for product #{product['id']}"
  end
end

def replace_tags(old_tags, tag_to_remove)
  old_tags.delete(tag_to_remove)
  return old_tags
end

def save_tags(product, new_tags)
  secure_put(
    "/products/#{product['id']}.json",
    {product: {id: product['id'], tags: new_tags}}
  )
end


def secure_get(relative_url)
  sleep DELAY_BETWEEN_REQUESTS
  url = SECURE_URL_BASE + relative_url
  result = NET_INTERFACE.get(url)
end

def secure_put(relative_url, params)
  sleep DELAY_BETWEEN_REQUESTS

  url = SECURE_URL_BASE + relative_url

  result = NET_INTERFACE.put(url, body: params)

  @outcomes[:responses].push({
    method: 'put', requested_url: url, body: result.body, code: result.code
  })
end

def put(url, params)
  NET_INTERFACE.put(url, query: params)
end

main
