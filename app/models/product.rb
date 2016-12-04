class Product < ActiveRecord::Base
  has_many :reviews

  def etl(code)
    product_info = get_product_from_ceneo(code)
    product = Product.new(product_info)
    reviews = get_reviews_from_ceneo(code)
    result = {
        'product' => product,
        'reviews' => reviews
    }
  end

  def get_product_from_ceneo(code)
    require 'open-uri'
    filename = 'http://www.ceneo.pl/' + code + '#tab=spec'
    doc = Nokogiri::HTML(open(filename))
    product = {
        "category" => doc.css('.breadcrumb:last-of-type a span').text,
        "notes" => doc.css('.ProductSublineTags').text,
        "brand" => doc.css('.specs-group:first-of-type table tbody tr:first-of-type td ul li a').text,
        "model" => doc.css('h1.product-name').text,
        "code" => code
    }
  end

  def get_reviews_from_ceneo(code)

    filename = 'http://www.ceneo.pl/' + code + '#tab=reviews'
    doc = Nokogiri::HTML(open(filename))

    reviews = doc.css('.product-review')
    reviews_content = []
    i = 0
    reviews.each { |review|
      reviews_content[i] = parse_review(review)
      i +=1
    }

    pagination = doc.css('.pagination ul li a')
    pag_count = pagination.size
    if pag_count > 1
      pagination.each { |site|
        filename = 'http://www.ceneo.pl/' + site['href']
        doc = Nokogiri::HTML(open(filename))
        reviews = doc.css('.product-review')
        reviews.each { |review|
          reviews_content[i] = parse_review(review)
          i +=1
        }
      }
    end
    reviews_content
  end


  def parse_review(review)

    pros_array = []
    cons_array = []
    i = j = 0

    pros = review.css('.pros-cell ul li')
    pros.each { |value|
      pros_array[i] = value.text
      i +=1
    }

    cons = review.css('.cons-cell ul li')
    cons.each { |value|
      cons_array[j] = value.text
      j +=1
    }

    date = review.css('.review-time time')

    score = review.css('.review-score-count').text

    code = review.css('.vote-yes')

    review_info = {
        'author' => review.css('.product-reviewer').text,
        'pros' => pros_array.to_json,
        'cons' => cons_array.to_json,
        'summary' => review.css('.product-review-body').text,
        'score' => score[0...1],
        'time' => date[0]['datetime'],
        'recommendation' => review.css('.product-recommended').text,
        'useful' => review.css('.vote-yes span').text,
        'not_useful' => review.css('.vote-no span').text,
        'code' => code[0]['data-review-id']
    }
  end

  def check_reviews_and_update(product)
    new_reviews = get_reviews_from_ceneo(product.code)
    new_reviews.each { |new_review|
      old_review = Review.find_by_code(new_review['code'])
      if old_review == nil
        new_review['product_id'] = product.id
        review = Review.new(new_review)
        review.save
      else
        old_review.update(new_review)
      end
    }
  end

  def extract(code, directory)
    require 'open-uri'

    prod_filename = 'http://www.ceneo.pl/' + code + '#tab=spec'
    download = open(prod_filename)
    name = "#{directory}/#{code}.html"
    open(name, 'w')
    IO.copy_stream(download, name)

    review_filename_1 = 'http://www.ceneo.pl/' + code + '#tab=reviews'
    download = open(review_filename_1)
    name = "#{directory}/#{code}_reviews_1.html"
    open(name, 'w')
    IO.copy_stream(download, name)
    reviews_amount = Nokogiri::HTML(download).css('.page-tab.reviews').text
    reviews_amount = /[0-9]+/.match(reviews_amount)[0].to_i
    pagination = reviews_amount/10
    last = reviews_amount%10
    if last > 0
      pagination +=1
    end

    i = 1
    if pagination > 1
      while i < pagination
        number = (i+1).to_s
        filename = "http://www.ceneo.pl/#{code}/opinie-#{number}"
        download = open(filename)
        name = "#{directory}/#{code}_reviews_#{number}.html"
        open(name, 'w')
        IO.copy_stream(download, name)
        i +=1
      end
    end
  end

end
