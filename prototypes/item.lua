local GRAPHICSPATH = "__port-crane-loader__/graphics/"

local function make_item(name, order)
  return {
    type = "item",
    name = name,
    icon = GRAPHICSPATH .. "icons/port_crane_icon.png",
    icon_size = 64,
    subgroup = "logistic-network",
    order = order,
    place_result = name,
    stack_size = 50
  }
end

data:extend({
    make_item("port-crane", "z[port-crane]-a[crane]")
})
