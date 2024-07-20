class Repository
  POSTS = {}
  COMMENTS = {}

  class << self
    def post(id)
      POSTS.fetch(id)
    end

    def comment(id)
      COMMENTS.fetch(id)
    end

    def add_post(title, id = Time.zone.now.to_i.to_s)
      post = {
        id: id,
        title: title,
        comments: [],
      }
      POSTS[post[:id]] = post
      post
    end

    def add_comment(post_id, message)
      comment = {
        id: Time.zone.now.to_i.to_s,
        message: message,
      }
      parent = post(post_id)
      parent[:comments] << comment
      COMMENTS[comment[:id]] = comment
      
      SubscriptionsSchema.subscriptions.trigger(:comment_added_to_post, { post_id: parent[:id] }, comment)
      comment
    end
  end
end

Repository.add_post("How to walk, talk, and chew gum", "1")
