class ProductsController < ApplicationController
  before_action :set_product, only: [:show, :edit, :update, :destroy, :delete_reviews]

  # GET /products
  # GET /products.json
  # Get list of products that have status loaded
  def index
    @products = Product.where(:status => 'loaded')
  end

  # GET /products/extracted
  # Get list of products that have status extracted
  def extracted
    @products = Product.where(:status => 'extracted')
    render :index
  end

  # GET /products/transformed
  # Get list of products that have status transformed
  def transformed
    @products = Product.where(:status => 'transformed')
    render :index
  end

  # GET /products/1
  # GET /products/1.json
  # Get specific product and its reviews
  def show
    @reviews = @product.reviews
    respond_to do |format|
      format.html
      format.csv { send_data @reviews.to_csv }
    end
  end

  # GET /products/new
  # Create new product - show form
  def new
    @product = Product.new
  end

  # GET /products/1/edit
  # Edit existing product (update reviews, process entry once again)
  def edit
    if @product.status == 'extracted'
      respond_to do |format|
        format.html { render :transform_view, id: @product.id, notice: 'Product already extracted, wanna transform?' }
      end
    elsif @product.status == 'transformed'
      respond_to do |format|
        format.html { render :load_view, id: @product.id, notice: 'Product already transformed, wanna transform?' }
      end
    end
  end

  # POST /products
  # POST /products.json
  # Create new product
  def create
    existing_prod = Product.where(:code => product_params["code"]).first
    if existing_prod == nil
      @product = Product.new(product_params)
      if is_etl?
        result = @product.etl(product_params["code"])
        if result
          @product = result['product']
          if @product.save
            result['reviews'].each { |review|
              review['product_id'] = @product.id
              review = Review.new(review)
              review.save
            }
            size = result['reviews'].size
            respond_to do |format|
              flash.now[:alert] = "Product was successfully created. It has #{size} reviews."
              format.html { render :show, id: @product.id, notice: "Product was successfully created. It has #{size} reviews." }
            end
          else
            respond_to do |format|
              format.html { render :new }
            end
          end
        else
          respond_to do |format|
            format.html { redirect_to '/products/new', notice: 'There is no product with such code on Ceneo' }
          end
        end
      end
      if is_extract?
        extract(product_params)
      end
    else
      respond_to do |format|
        format.html { redirect_to existing_prod, notice: 'Product already exists. Wanna check for updates?' }
      end
    end
  end

  # GET /products/1/transform_view
  # Transform extracted data - show form
  def transform_view
    @product = Product.find(params[:product_id])
  end

  # PATCH/PUT /products/1/transform
  # Transform extracted data
  def transform
    require 'json'
    @product = Product.find(params[:product_id])
    if @product.status == 'extracted'
      data = @product.transform_data(@product.code)
      File.open("public/tmp/#{product_params["code"]}.json", "w") do |f|
        f.write(data.to_json)
      end
      @product.status = "transformed"
      if @product.save
        FileUtils.rm_rf("#{Rails.root}/public/tmp/#{product_params["code"]}/extract")
        respond_to do |format|
          flash.now[:alert] = 'Data transformed successfully. Created 1 JSON file. Wanna continue'
          format.html { render :load_view, id: @product.id, notice: 'Data transformed successfully. Created 1 JSON file. Wanna continue?' }
        end
      else
        respond_to do |format|
          flash.now[:alert] = 'Data could not have been transformed. Try again later.'
          format.html { render :transform, id: @product.id, notice: 'Data could not have been transformed. Try again later.' }
        end
      end
    end
  end

  # GET /products/1/load_view
  # Load transformed data - show form
  def load_view
    @product = Product.find(params[:product_id])
  end

  # PATCH/PUT /products/1/load
  # Load transformed data to database
  def load
    @product = Product.find(params[:product_id])
    file = File.read("public/tmp/#{product_params["code"]}.json")
    data = JSON.parse(file)
    puts data["product"]
    if @product.status == 'transformed'
      @product.category = data["product"]['category']
      @product.brand = data["product"]['brand']
      @product.model = data["product"]['model']
      @product.notes = data["product"]['notes']
      @product.status = 'loaded'
      if @product.save
        data['reviews'].each { |rev|
          review = Review.new(rev)
          review.product_id = @product.id
          review.save
        }
        size = data['reviews'].size
        FileUtils.rm_rf("#{Rails.root}/public/tmp/#{product_params["code"]}")
        File.delete("#{Rails.root}/public/tmp/#{product_params["code"]}.json")
        respond_to do |format|
          format.html { render :show, id: @product.id, notice: "Data has been saved. Loaded #{size} reviews to database." }
        end
      else
        respond_to do |format|
          format.html { render :load_view, id: @product.id, notice: 'Data could not have been loaded to database. Try again later or contact with admin.' }
        end
      end
    end
  end

  # PATCH/PUT /products/1
  # PATCH/PUT /products/1.json
  # Update reviews of product
  def update
    if is_etl?
      product_info = @product.get_product_from_ceneo(@product.code)
      if product_info
        @product.check_reviews_and_update(@product)
        respond_to do |format|
          if @product.update(product_info)
            format.html { redirect_to @product, notice: 'Product was successfully updated.' }
          else
            format.html { render :edit }
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to '/products/new', notice: 'There is no product with such code on Ceneo' }
        end
      end
    end
    if is_extract?
      @reviews = Review.where(:product_id => @product.id)
      i = 0
      count_reviews = @reviews.size
      @reviews.each { |review|
        review.destroy
        i +=1
      }
      if i == count_reviews
        @product.destroy
        extract(product_params)
      end
    end
  end


  # GET /product/1/delete_reviews
  # Delete all reviews of specific product
  def delete_reviews

    if @product.reviews.destroy_all
      respond_to do |format|
        format.html { redirect_to products_url, notice: 'All reviews successfully destroyed' }
      end
    else
      respond_to do |format|
        format.html { redirect_to products_url, notice: 'Error occured. Try again.' }
      end
    end

  end

  # GET /product/1/
  # Delete product with all its reviews
  def destroy
    if @product.reviews.destroy_all
      @product.destroy
    end

    respond_to do |format|
      format.html { redirect_to products_path, notice: 'Product successfully destroyed' }
    end
  end

  private

  # Set product variable depending on id
  def set_product
    if params[:id]
      @product = Product.find(params[:id])
    else
      @product = Product.find(params[:product_id])
    end
  end

  # Check if user clicked ETL button
  def is_etl?
    params[:commit] == "ETL"
  end

  # Check if user clicked Extract button
  def is_extract?
    params[:commit] == "Extract"
  end

  # Initialize extraction process
  def extract(params)
    @product = Product.new(params)
    directory_name = "#{Rails.root}/public/tmp/#{params[:code]}/extract"
    if !File.exists?(directory_name)
      FileUtils.mkdir_p(directory_name)
    end
    status = @product.extract(params[:code], directory_name)
    if status
      @product.status = "extracted"
      if @product.save
        respond_to do |format|
          flash.now[:alert] = "Data extracted successfully. Created #{status} files. Wanna continue?"
          format.html { render :transform_view, id: @product.id, notice: "Data extracted successfully. Created #{status} files. Wanna continue?" }
        end
      else
        respond_to do |format|
          format.html { render :new }
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to '/products/new', notice: 'There is no product with such code on Ceneo' }
      end
    end
  end

  # Set product fillable parameters
  def product_params
    params.require(:product).permit(:code, :brand, :model, :type, :notes)
  end

end
