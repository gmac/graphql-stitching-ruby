Rails.application.routes.draw do
  mount ActionCable.server, at: "/cable"

  post "/graphql", to: "graphql#execute"
  get  "/graphql/event", to: "graphql#event"
  
  root "graphql#client"
end
