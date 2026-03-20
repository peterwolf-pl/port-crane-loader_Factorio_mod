local util = require("util")

local GRAPHICSPATH = "__port-crane-loader__/graphics/"
local BASE_EXTENSION_SPEED = 0.6
local BASE_ROTATION_SPEED = 0.02

local function crane_speed_multiplier()
  local setting = settings.startup["port-crane-transfer-speed-multiplier"]
  local value = setting and setting.value or 1

  if type(value) ~= "number" or value <= 0 then
    return 1
  end

  return value
end

local function sprite4way_from_sheet(filename, x_by_dir, w, h, opts)
  opts = opts or {}

  local function one(xoff, extra)
    extra = extra or {}
    local s = {
      filename = filename,
      priority = opts.priority or "extra-high",
      width = w,
      height = h,
      x = xoff + (extra.x_add or 0),
      y = (opts.y or 0) + (extra.y_add or 0),
      frame_count = 1,
      direction_count = 1,
      scale = opts.scale or 1,
      shift = extra.shift or opts.shift
    }

    if opts.sort_y_offset then s.sort_y_offset = opts.sort_y_offset end


    if opts.render_layer then s.render_layer = opts.render_layer end
    if opts.draw_as_shadow then
      s.draw_as_shadow = true
      -- keep shadow under everything; also prevents weird "shadow over objects" issues
      s.render_layer = opts.shadow_render_layer or "floor"
    end

    return s
  end

  return {
    north = one(x_by_dir.north, opts.north),
    east  = one(x_by_dir.east,  opts.east),
    south = one(x_by_dir.south, opts.south),
    west  = one(x_by_dir.west,  opts.west)
  }
end

-- Observed in-game alignment for this sheet: N, E, S, W (left-to-right), each 500x500 in a 2000x500 image.
local X_OFF_4DIR = {
  north = 0,
  east  = 500,
  south = 1000,
  west  = 1500
}

-- Shadow crop per direction (measured from port_crane_platform_4dir_ss.png).
-- Goal: shadow from one crane must not spill onto the crane placed next to it.
local SHADOW_CROP = {
  -- within each 500x500 slot: x_add, y_add, width, height, plus shift correction
  south = { x_add = 189, y_add = 127, w = 304, h = 253, shift = util.by_pixel(91, 3.5) },
  west  = { x_add = 144, y_add = 190, w = 356, h = 114, shift = util.by_pixel(72, -3) },
  north = { x_add = 189, y_add = 126, w = 304, h = 254, shift = util.by_pixel(91, 3) },
  east  = { x_add = 179, y_add = 195, w = 321, h = 103, shift = util.by_pixel(89.5, -3.5) }
}

local function sprite4way_layers(base_filename, shadow_filename)
  -- Base layer: always above ships
  local base = sprite4way_from_sheet(
    base_filename,
    X_OFF_4DIR,
    500,
    500,
    { render_layer = "higher-object-above", sort_y_offset = 5 }
  )

  -- Shadow: cropped per direction + corrected shift, drawn as shadow on "floor"
  local shadow = sprite4way_from_sheet(
    shadow_filename,
    X_OFF_4DIR,
    500,  -- placeholders; overridden per direction below
    500,
    {
      draw_as_shadow = true,
      shadow_render_layer = "floor",
      south = { x_add = SHADOW_CROP.south.x_add, y_add = SHADOW_CROP.south.y_add, shift = SHADOW_CROP.south.shift },
      west  = { x_add = SHADOW_CROP.west.x_add,  y_add = SHADOW_CROP.west.y_add,  shift = SHADOW_CROP.west.shift },
      north = { x_add = SHADOW_CROP.north.x_add, y_add = SHADOW_CROP.north.y_add, shift = SHADOW_CROP.north.shift },
      east  = { x_add = SHADOW_CROP.east.x_add,  y_add = SHADOW_CROP.east.y_add,  shift = SHADOW_CROP.east.shift }
    }
  )

  -- Replace shadow widths/heights per direction (cropped rectangles)
  shadow.south.width, shadow.south.height = SHADOW_CROP.south.w, SHADOW_CROP.south.h
  shadow.west.width,  shadow.west.height  = SHADOW_CROP.west.w,  SHADOW_CROP.west.h
  shadow.north.width, shadow.north.height = SHADOW_CROP.north.w, SHADOW_CROP.north.h
  shadow.east.width,  shadow.east.height  = SHADOW_CROP.east.w,  SHADOW_CROP.east.h

  return {
    north = { layers = { base.north, shadow.north } },
    east  = { layers = { base.east,  shadow.east  } },
    south = { layers = { base.south, shadow.south } },
    west  = { layers = { base.west,  shadow.west  } }
  }
end

-- Empty hand sprites (we hide inserter hands; crane uses only platform_picture)
local empty = {
  filename = "__core__/graphics/empty.png",
  priority = "extra-high",
  width = 1,
  height = 1
}

local function resolve_inserter_prototype(name)
  local inserters = data.raw["inserter"]

  if inserters[name] then
    return inserters[name], name
  end

  if name == "stack-inserter" and inserters["bulk-inserter"] then
    return inserters["bulk-inserter"], "bulk-inserter"
  end

  error("Missing inserter prototype: " .. name)
end

local function make_port_crane(name, base, pickup, drop, icon)
  local base_prototype, resolved_name = resolve_inserter_prototype(base)
  local e = table.deepcopy(base_prototype)
  e.name = name
  e.icon = icon or e.icon
  e.icon_size = 64
  e.minable = {mining_time = 2, result = "port-crane"}
  e.max_health = 350  
  e.render_layer = "higher-object-above"
  e.selection_priority = 200

  -- Shape requirement:
  -- 3x3 on land (collision), plus 3x3 over waterway (selection + reach).
  -- Boxes defined for NORTH-facing; Factorio rotates them for other directions.
  -- Land occupies the "back" part, so the entity can be placed on shore.
  e.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}        -- 3x3 (back/land), no overlap with water
  e.selection_box = {{-1.0, -1.0}, {1.0, 1.0}}       -- land + water reach

  e.energy_per_movement = "20kJ"
  e.energy_per_rotation = "20kJ"
  local speed_multiplier = crane_speed_multiplier()
  e.extension_speed = BASE_EXTENSION_SPEED * speed_multiplier
  e.rotation_speed = BASE_ROTATION_SPEED * speed_multiplier
  e.rotatable = true

  -- Functional vectors
  e.pickup_position = pickup
  e.insert_position = drop
  e.allow_custom_vectors = true
  if resolved_name == "bulk-inserter" then
    e.bulk = true
    e.stack = nil
  else
    e.stack = true
  end
  e.filter_count = 5
  e.fast_replaceable_group = "port-crane"
  e.next_upgrade = nil
  e.draw_held_item = false

  -- Crane graphics (platform_picture)
  -- Keep the inserter body invisible; the visible crane is drawn by a separate overlay entity above ships.
  local empty_platform = {
    filename = "__core__/graphics/empty.png",
    priority = "extra-high",
    width = 1,
    height = 1,
    frame_count = 1,
    direction_count = 1
  }
  e.platform_picture = {
    north = { layers = { empty_platform } },
    east  = { layers = { empty_platform } },
    south = { layers = { empty_platform } },
    west  = { layers = { empty_platform } }
  }

  e.hand_base_picture = empty
  e.hand_closed_picture = empty
  e.hand_open_picture = empty
  e.hand_base_shadow = empty
  e.hand_closed_shadow = empty
  e.hand_open_shadow = empty

  return e
end

-- Vectors are for NORTH-facing:
-- - loader: pickup from land side (back), drop over water side (front)
-- - unloader: reverse
local pickup_land = {0, 2.0}
local drop_water  = {0, -3.5}

local crane = make_port_crane(
  "port-crane",
  "stack-inserter",
  pickup_land,
  drop_water,
  GRAPHICSPATH .. "icons/port_crane_icon.png"
)




-- Decorative visual entities (drawn above rolling stock, like rail loader)
local function make_visual(name, base_x, crop)
  return {
    type = "simple-entity-with-owner",
    name = name,
    icon = GRAPHICSPATH .. "icons/port_crane_icon.png",
    icon_size = 64,
    flags = {"placeable-off-grid", "not-on-map"},
    hidden = true,
    selectable_in_game = false,
    collision_mask = {layers = {}, not_colliding_with_itself = true},
    collision_box = {{0, 0}, {0, 0}},
    selection_box = {{0, 0}, {0, 0}},
    render_layer = "higher-object-above",
    picture = {
      layers = {
        {
          filename = GRAPHICSPATH .. "entity/port_crane/port_crane_platform_4dir.png",
          priority = "extra-high",
          width = 500,
          height = 500,
          x = base_x,
          y = 0,
          frame_count = 1,
          direction_count = 1,
          shift = util.by_pixel(0, 0),
          sort_y_offset = 5,
          scale = 1.5,
          render_layer = "higher-object-above"

        },
        {
          filename = GRAPHICSPATH .. "entity/port_crane/port_crane_platform_4dir_ss.png",
          priority = "extra-high",
          width = crop.w,
          height = crop.h,
          x = base_x + crop.x_add,
          y = crop.y_add,
          frame_count = 1,
          direction_count = 1,
          scale = 1.5,
          shift = crop.shift,
          draw_as_shadow = true,
          render_layer = "floor"

        }
      }
    }
  }
end

-- Names per direction (Factorio directions)
local crane_vis_south = make_visual("port-crane-visual-south", X_OFF_4DIR.south, SHADOW_CROP.south)
local crane_vis_west  = make_visual("port-crane-visual-west",  X_OFF_4DIR.west,  SHADOW_CROP.west)
local crane_vis_north = make_visual("port-crane-visual-north", X_OFF_4DIR.north, SHADOW_CROP.north)
local crane_vis_east  = make_visual("port-crane-visual-east",  X_OFF_4DIR.east,  SHADOW_CROP.east)


data:extend({crane, crane_vis_north, crane_vis_east, crane_vis_south, crane_vis_west})
