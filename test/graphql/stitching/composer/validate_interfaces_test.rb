# frozen_string_literal: true

require "test_helper"

describe 'GraphQL::Stitching::Composer, validate interfaces' do
  def test_errors_for_unmatched_types_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: String! }
      type Gizmo implements Widget { id: ID! value: String! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! value: Int! }
      type Query { b: Gadget }
    |

    assert_error('Field type of Gadget.value must match merged interface Widget.value', ValidationError) do
       compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_errors_for_unmatched_list_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: [String]! }
      type Gizmo implements Widget { id: ID! value: [String]! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! value: String! }
      type Query { b: Gadget }
    |

    assert_error('Field type of Gadget.value must match list structure of merged interface Widget.value', ValidationError) do
       compose_definitions({ "a" => a, "b" => b })
    end
  end

  def test_errors_for_unmatched_nullability_in_inherited_interfaces
    a = %|
      interface Widget { id: ID! value: String! }
      type Gizmo implements Widget { id: ID! value: String! }
      type Query { a: Gizmo }
    |
    b = %|
      interface Widget { id: ID! }
      type Gadget implements Widget { id: ID! value: String }
      type Query { b: Gadget }
    |

    assert_error('Field type of Gadget.value must match non-null status of merged interface Widget.value', ValidationError) do
       compose_definitions({ "a" => a, "b" => b })
    end
  end
end
