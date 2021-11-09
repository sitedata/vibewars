class CollectionsController < ApplicationController
  before_action :get_collection, except: [:index]

  def index
    @collections = Collection.all.order(name: :asc)

    respond_to do |format|
      format.html
      format.json { render json: { collections: @collections } }
    end
  end

  def show
    compare = @collection.assets.where.not(image_url: nil).where('updated_at < ?', Time.current - 5.minutes).order(votes_count: :asc).limit(500)
    @item_first = compare.sample
    @item_last = compare.sample

    if @wallet.present?
      @recent_vote_count = @collection.votes.where('wallet_id = ? AND created_at > ?', @wallet.id, Time.current - 60.minutes).count
    else
      @recent_vote_count = @collection.votes.where('ip_address = ? AND created_at > ?', request.remote_ip, Time.current - 60.minutes).count
    end

    @vote_throttle = @recent_vote_count > 300 ? true : false
    
    respond_to do |format|
      format.html
      format.json { render json: { collection: @collection, total_items: @collection.assets.count, total_votes: @collection.votes.count, percent_done: @collection.percentage_voted, rank_confidence: @collection.rank_confidence, item_first: @item_first, item_last: @item_last } }
    end

    if @item_first == @item_last or @item_first.blank? or @item_last.blank? 
      redirect_to collection_path(@collection.slug)
    end
  end

  def ranking
    @assets = @collection.assets

    if params[:trait].present?
      params[:trait].each do |trait|
        @assets = @assets.where('traits @> ?', [{trait_type: trait['type']}, {value: trait['value']}].to_json)
      end
    end

    @assets = @assets.where('rank > 0').order(rank: :asc).page params[:page]

    respond_to do |format|
      format.html
      format.json { render json: { collection: @collection, total_items: @collection.assets.count, total_votes: @collection.votes.count, percent_done: @collection.percentage_voted, rank_confidence: @collection.rank_confidence, assets: @assets } }
    end
  end

  def leaderboard
    @discord = Discordrb::Bot.new(token: ENV['DISCORD'])

    @leaders = Rails.cache.fetch("query-leaders-#{@collection.id}", expires_in: 1.hour) do
      @collection.votes.where("wallet_id IS NOT NULL OR discord_user_id IS NOT NULL").group(:wallet_id, :discord_user_id).order(count_all: :desc).count
    end
  end

private
  def get_collection
    if /\A0x[a-fA-F0-9]{40}\z/i.match(params[:id])
      @collection = Collection.where(address: params[:id]).first
      redirect_to ranking_collection_path(@collection.slug)
    else
      @collection = Collection.where(slug: params[:id]).first
    end
  end

end
