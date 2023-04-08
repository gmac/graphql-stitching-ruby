# frozen_string_literal: true

require "test_helper"

describe "GraphQL::Stitching::Planner, defer/stream directives" do
  def setup
    @people_sdl = %|
      type Person {
        id: ID!
        name: String!
        bio: String!
        thing: Thing!
      }
      type Thing {
        name: String!
        moreStuff: String!
        person: Person!
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
        _person(id: ID!): Person @stitch(key: "id")
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
        person: Person!
      }
      type Query {
        _person(id: ID!): Person @stitch(key: "id")
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
          ...HomeWorldFragment @defer(label: "homeWorld")
          name
          thing {
            ... @defer(label: "thing1") {
              moreStuff
              person {
                name
              }
            }
            ...Woof @defer(label: "thing2")
          }
          films @stream(initialCount: 2, label: "films") {
            title
            person {
              name
            }
          }
        }
      }
      fragment Woof on Thing {
        moreStuff
      }
      fragment HomeWorldFragment on Person {
        __typename
        bio
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