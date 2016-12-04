class ProductsController < ApplicationController
  before_action :set_product, only: [:show, :edit, :update]

  # GET /products
  # GET /products.json
  def index
    @products = Product.all
  end

  # GET /products/1
  # GET /products/1.json
  def show
    @reviews = @product.reviews
    respond_to do |format|
      format.html
      format.csv { send_data @reviews.to_csv }
    end
  end

  # GET /products/new
  def new
    @product = Product.new
  end

  # GET /products/1/edit
  def edit
  end

  # POST /products
  # POST /products.json
  def create
    existing_prod = Product.where(:code => product_params["code"]).first
    if existing_prod == nil
      @product = Product.new(product_params)
      if is_etl?
        result = @product.etl(product_params["code"])
        if result['product'].save
          result['reviews'].each { |review|
            review['product_id'] = result['product'].id
            review = Review.new(review)
            review.save
          }
          format.html { redirect_to result.product, notice: 'Product was successfully updated.' }
          format.json { render :show, status: :ok, location: result.product }
        end
      end
      if is_extract?
        directory_name = "#{Rails.root}/public/tmp/#{product_params["code"]}"
        if !File.exists?(directory_name)
          Dir.mkdir(directory_name)
        end
        @product.extract(product_params["code"], directory_name)
        Rails.cache.write(product_params["code"], product_params["code"])
        if @product.save
          respond_to do |format|
            format.html { render :transform_view, id: @product.id, notice: 'Data extracted successfully. Wanna continue?' }
            format.json { render :show, status: :created, location: product }
          end
        else
          format.html { render :new }
          format.json { render json: @product.errors, status: :unprocessable_entity }
        end

      end
    else
      respond_to do |format|
        format.html { redirect_to @existing_prod, notice: 'Product already exists. Wanna check for updates?' }
        format.json { render :show, status: :created, location: @existing_prod }
      end
    end
  end


  # PATCH/PUT /products/1
  # PATCH/PUT /products/1.json
  def update
    product_info = @product.get_product_from_ceneo(@product.code)
    @product.check_reviews_and_update(@product)
    respond_to do |format|
      if @product.update(product_info)
        format.html { redirect_to @product, notice: 'Product was successfully updated.' }
        format.json { render :show, status: :ok, location: @product }
      else
        format.html { render :edit }
        format.json { render json: @product.errors, status: :unprocessable_entity }
      end
    end
  end

  def delete_reviews

    @reviews = Review.where(:product_id => params["product_id"])
    puts params["product_id"]

    @reviews.each { |review|
      review.destroy
    }
    respond_to do |format|
      format.html { redirect_to products_url, notice: 'All reviews successfully destroyed' }
      format.json { head :no_content }
    end
  end

  def transform_view

  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_product
    @product = Product.find(params[:id])
  end

  def is_etl?
    params[:commit] == "ETL"
  end

  def is_extract?
    params[:commit] == "Extract"
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def product_params
    params.require(:product).permit(:code, :brand, :model, :type, :notes)
  end
end
