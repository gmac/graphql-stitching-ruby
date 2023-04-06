# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, defer/stream directives" do
  def setup
    @people_sdl = %|
      type Person {
        id: ID!
        name: String!
      }
      type Query {
        person(id: ID!): Person @stitch(key: "id")
      }
    |

    @worlds_sdl = %|
      type Person {
        id: ID!
        homeworld: World!
      }
      type World {
        id: ID!
        name: String!
      }
      type Query {
        person(id: ID!): Person @stitch(key: "id")
        world(id: ID!): World
      }
    |

    @films_sdl = %|
      type Person {
        id: ID!
        films: [Film!]!
      }
      type Film {
        id: ID!
        title: String!
      }
      type Query {
        person(id: ID!): Person @stitch(key: "id")
        film(id: ID!): Film
      }
    |

    @supergraph = compose_definitions({
      "people" => @people_sdl,
      "worlds" => @worlds_sdl,
      "films" => @films_sdl,
    })
  end

  def test_plan_defer_stream_directives
    document = %|
      query {
        person(id: "cGVvcGxlOjE=") {
          ...HomeWorldFragment @defer(label: "homeWorldDefer")
          name
          films @stream(initialCount: 2, label: "filmsStream") {
            title
          }
        }
      }
      fragment HomeWorldFragment on Person {
        homeworld {
          name
        }
      }
    |

    pp GraphQL::Stitching::Planner.new(
      supergraph: @supergraph,
      request: GraphQL::Stitching::Request.new(document),
    ).perform.to_h
  end
end