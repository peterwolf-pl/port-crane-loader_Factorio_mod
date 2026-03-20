local base_inserter_item = data.raw["item"]["bulk-inserter"] and "bulk-inserter" or "stack-inserter"

local function make_recipe(name)
  return {
    type = "recipe",
    name = name,
    enabled = true,
    ingredients = {
      {type="item", name=base_inserter_item, amount=1},
      {type="item", name="steel-plate", amount=20},
      {type="item", name="electronic-circuit", amount=10}
    },
    results = {{type="item", name=name, amount=1}}
  }
end

data:extend({
  make_recipe("port-crane")
})
