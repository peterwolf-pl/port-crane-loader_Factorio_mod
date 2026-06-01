local ALLOWED_STRAIGHT_WATERWAY = {
  ["straight-waterway"] = true,
  ["legacy-straight-waterway"] = true
}

local DISALLOWED_WATERWAY = {
  ["curved-waterway-a"] = true,
  ["curved-waterway-b"] = true,
  ["half-diagonal-waterway"] = true,
  ["legacy-curved-waterway"] = true
}

local CRANE_NAMES = {
  ["port-crane"] = true
}

local function is_crane(ent)
  return ent and ent.valid and CRANE_NAMES[ent.name] == true
end


local LAND_SIDE_DISTANCE = 2.0
local WATER_SIDE_DISTANCE = 3.5

-- Crane mode:
-- "load"   = pickup from land (back), drop over water (front)
-- "unload" = pickup from water (front), drop to land (back)
local function ensure_globals()
  -- Factorio 2.0: persistent state table is `storage` (pre-2.0 it was `global`).
  storage.port_crane = storage.port_crane or {}
  storage.port_crane.mode_by_unit = storage.port_crane.mode_by_unit or {}
  storage.port_crane.visual_by_unit = storage.port_crane.visual_by_unit or {}
end


local function visual_name_for_dir(dir)
  if dir == defines.direction.north then return "port-crane-visual-north" end
  if dir == defines.direction.east  then return "port-crane-visual-east" end
  if dir == defines.direction.south then return "port-crane-visual-south" end
  if dir == defines.direction.west  then return "port-crane-visual-west" end
  return "port-crane-visual-north"
end

local function destroy_crane_visual(crane)
  if not (crane and crane.valid and crane.unit_number) then return end
  ensure_globals()

  for _, ent in pairs(crane.surface.find_entities_filtered{
    position = crane.position,
    radius = 0.35,
    name = {"port-crane-visual-north","port-crane-visual-east","port-crane-visual-south","port-crane-visual-west"}
  }) do
    if ent and ent.valid then
      ent.destroy()
    end
  end

  storage.port_crane.visual_by_unit[crane.unit_number] = nil
end

local function create_crane_visual(crane)
  if not (crane and crane.valid and crane.unit_number) then return end
  ensure_globals()

  destroy_crane_visual(crane)

  local visual = crane.surface.create_entity{
    name = visual_name_for_dir(crane.direction),
    position = crane.position,
    force = crane.force,
    create_build_effect_smoke = false
  }

  if visual and visual.valid then
    storage.port_crane.visual_by_unit[crane.unit_number] = true
  end
end

local function offsets_for_dir(dir)
  -- Returns {land={dx,dy}, water={dx,dy}} relative to ent.position
  if dir == defines.direction.north then
    return { land = {0,  LAND_SIDE_DISTANCE}, water = {0, -WATER_SIDE_DISTANCE} }
  elseif dir == defines.direction.south then
    return { land = {0, -LAND_SIDE_DISTANCE}, water = {0,  WATER_SIDE_DISTANCE} }
  elseif dir == defines.direction.east then
    return { land = {-LAND_SIDE_DISTANCE, 0}, water = { WATER_SIDE_DISTANCE, 0} }
  elseif dir == defines.direction.west then
    return { land = { LAND_SIDE_DISTANCE, 0}, water = {-WATER_SIDE_DISTANCE, 0} }
  end
  return { land = {0, LAND_SIDE_DISTANCE}, water = {0, -WATER_SIDE_DISTANCE} }
end

local function set_crane_mode(ent, mode)
  if not is_crane(ent) then return end
  if not ent.unit_number then return end
  ensure_globals()

  local off = offsets_for_dir(ent.direction)
  local px, py = ent.position.x, ent.position.y

  local function abspos(rel)
    return {x = px + rel[1], y = py + rel[2]}
  end

  if mode == "unload" then
    pcall(function()
      ent.pickup_position = abspos(off.water)
      ent.drop_position = abspos(off.land)
    end)
    storage.port_crane.mode_by_unit[ent.unit_number] = "unload"
  else
    pcall(function()
      ent.pickup_position = abspos(off.land)
      ent.drop_position = abspos(off.water)
    end)
    storage.port_crane.mode_by_unit[ent.unit_number] = "load"
  end
end

local function get_crane_mode(ent)
  ensure_globals()
  if ent and ent.valid and ent.unit_number then
    return storage.port_crane.mode_by_unit[ent.unit_number] or "load"
  end
  return "load"
end

local function toggle_crane_mode(ent, player_index)
  local cur = get_crane_mode(ent)
  local nxt = (cur == "load") and "unload" or "load"
  set_crane_mode(ent, nxt)

  if player_index and game and game.players and game.players[player_index] then
    local p = game.players[player_index]
    if p and p.valid then
      local key = (nxt == "load") and {"port-crane.mode-load"} or {"port-crane.mode-unload"}
      p.create_local_flying_text{ position = ent.position, text = key }
    end
  end
end


local function apply_crane_runtime_settings(ent)
  if not is_crane(ent) then return end
  ensure_globals()
  if ent.unit_number and not storage.port_crane.mode_by_unit[ent.unit_number] then
    storage.port_crane.mode_by_unit[ent.unit_number] = "load"
  end
  -- Clear legacy overrides so the crane follows normal bulk-inserter hand behavior.
  pcall(function()
    ent.inserter_stack_size_override = 0
  end)
  -- Apply current mode vectors
  set_crane_mode(ent, get_crane_mode(ent))
end

local function spill_item(surface, force, pos, name, count)
  if surface and surface.valid then
    surface.spill_item_stack{
      position = pos,
      stack = {name = name, count = count or 1},
      enable_looted = true,
      force = force,
      allow_belts = false
    }
  end
end

local function expected_rail_dir_ok(crane_dir, rail_dir)
  -- Waterway should be parallel to shore, and crane faces towards it.
  -- That means: rail runs PERPENDICULAR to crane facing.
  if crane_dir == defines.direction.north or crane_dir == defines.direction.south then
    return rail_dir == defines.direction.east or rail_dir == defines.direction.west
  end
  if crane_dir == defines.direction.east or crane_dir == defines.direction.west then
    return rail_dir == defines.direction.north or rail_dir == defines.direction.south
  end
  return false
end

local function offsets_water_3x3(crane_dir)
  local t = {}
  if crane_dir == defines.direction.north then
    for dx = -1, 1 do
      for dy = -1, -4, -1 do
        t[#t+1] = {dx = dx, dy = dy}
      end
    end
  elseif crane_dir == defines.direction.south then
    for dx = -1, 1 do
      for dy = 1, 4 do
        t[#t+1] = {dx = dx, dy = dy}
      end
    end
  elseif crane_dir == defines.direction.east then
    for dy = -1, 1 do
      for dx = 1, 4 do
        t[#t+1] = {dx = dx, dy = dy}
      end
    end
  elseif crane_dir == defines.direction.west then
    for dy = -1, 1 do
      for dx = -1, -4, -1 do
        t[#t+1] = {dx = dx, dy = dy}
      end
    end
  end
  return t
end



local function tile_is_water(t)
  if not (t and t.valid) then return false end

  -- Prefer Factorio 2.0 built-in collision layer names.
  local ok, res = pcall(function() return t.collides_with("water_tile") end)
  if ok then return res end

  -- Fallback for older mods / custom layers (avoid crashing if layer is unknown).
  ok, res = pcall(function() return t.collides_with("ground_tile") end)
  if ok then return not res end

  -- Last resort: name heuristic (Cargo Ships waterway tiles usually contain "water" / "waterway").
  local n = t.name or ""
  if n:find("waterway", 1, true) then return true end
  if n:find("water", 1, true) then return true end

  return false
end

local function shore_ok(surface, pos, crane_dir)
  -- Allow offshore placement when the waterway/shore are 1 or 2 tiles away along the crane axis.
  local fx, fy = 0, 0
  if crane_dir == defines.direction.north then fy = -1
  elseif crane_dir == defines.direction.south then fy = 1
  elseif crane_dir == defines.direction.east then fx = 1
  elseif crane_dir == defines.direction.west then fx = -1
  else return false end

  local has_water = false
  for d = 1, 2 do
    local front = surface.get_tile(pos.x + fx * d, pos.y + fy * d)
    if front and front.valid and tile_is_water(front) then
      has_water = true
      break
    end
  end

  local has_land = false
  for d = 1, 2 do
    local back = surface.get_tile(pos.x - fx * d, pos.y - fy * d)
    if back and back.valid and (not tile_is_water(back)) then
      has_land = true
      break
    end
  end

  return has_water and has_land
end

local function waterway_ok(surface, pos, crane_dir)
  -- Strict rules:
  -- - ONLY straight-waterway (or legacy-straight-waterway)
  -- - must cover a 3x3 area directly in front of the crane
  -- - must have correct orientation

  local offsets = offsets_water_3x3(crane_dir)
  if #offsets == 1 then return false end

  -- Reject if any disallowed waterway entity is in the 3x3 water area
  local area = {
    {pos.x - 3.2, pos.y - 3.2},
    {pos.x + 3.2, pos.y + 3.2}
  }
  -- Note: the 3x3 "water" area is further out, but we check per-tile below for strictness.
  -- This quick reject catches accidental curved pieces near the crane.
  local nearby = surface.find_entities_filtered{
    area = {{pos.x - 6, pos.y - 6}, {pos.x + 6, pos.y + 6}},
    type = {"straight-rail", "legacy-straight-rail", "curved-rail", "legacy-curved-rail"}
  }
  for _, r in pairs(nearby) do
    if r.valid and DISALLOWED_WATERWAY[r.name] then
      -- If disallowed is close to the required 3x3 region, reject.
      local dx = r.position.x - pos.x
      local dy = r.position.y - pos.y
      local forward = 0
      local sideways = 0
      if crane_dir == defines.direction.north then
        forward = -dy; sideways = math.abs(dx)
      elseif crane_dir == defines.direction.south then
        forward = dy; sideways = math.abs(dx)
      elseif crane_dir == defines.direction.east then
        forward = dx; sideways = math.abs(dy)
      elseif crane_dir == defines.direction.west then
        forward = -dx; sideways = math.abs(dy)
      end
      if forward >= 0.5 and forward <= 3.5 and sideways <= 2.0 then
        return false
      end
    end
  end

  -- For each tile in the 3x3 water region, require at least one allowed straight-waterway entity overlapping it.
  for _, o in pairs(offsets) do
    local tx = pos.x + o.dx
    local ty = pos.y + o.dy
    local ents = surface.find_entities_filtered{
      area = {{tx - 1.1, ty - 1.1}, {tx + 1.1, ty + 1.1}},
      type = {"straight-rail", "legacy-straight-rail"},
    }

    local ok_here = false
    for _, r in pairs(ents) do
      if r.valid and ALLOWED_STRAIGHT_WATERWAY[r.name] and expected_rail_dir_ok(crane_dir, r.direction) then
        ok_here = true
        break
      end
    end

    if not ok_here then
      return false
    end
  end

  return true
end

local function invalidate_crane(entity, player_index, reason)
  local surface = entity.surface
  local force = entity.force
  local pos = entity.position
  local name = entity.name

  destroy_crane_visual(entity)
  entity.destroy()
  spill_item(surface, force, pos, name, 1)

  if player_index and game.players[player_index] and game.players[player_index].valid then
    game.players[player_index].print(reason or "[Port Crane] Invalid placement.")
  end
end

local function on_built_entity(e)
  local ent = e.created_entity or e.entity
  if not is_crane(ent) then return end
  if not (ent.surface and ent.surface.valid) then return end

  apply_crane_runtime_settings(ent)

  if not shore_ok(ent.surface, ent.position, ent.direction) then
    invalidate_crane(ent, e.player_index, "[Port Crane] Must be placed offshore, with waterway 1 or 2 tiles from shore.")
    return
  end

  create_crane_visual(ent)
end

script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)
script.on_event(defines.events.script_raised_built, on_built_entity)
script.on_event(defines.events.script_raised_revive, on_built_entity)


local function on_removed_entity(e)
  local ent = e.entity
  if not is_crane(ent) then return end
  destroy_crane_visual(ent)
  ensure_globals()
  if ent.unit_number then
    storage.port_crane.mode_by_unit[ent.unit_number] = nil
  end
end

script.on_event(defines.events.on_pre_player_mined_item, on_removed_entity)
script.on_event(defines.events.on_robot_pre_mined, on_removed_entity)
script.on_event(defines.events.on_entity_died, on_removed_entity)
script.on_event(defines.events.script_raised_destroy, on_removed_entity)

script.on_event(defines.events.on_entity_cloned, function(e)
  local src = e.source
  local dst = e.destination
  if is_crane(src) and is_crane(dst) then
    apply_crane_runtime_settings(dst)
    create_crane_visual(dst)
  end
end)

script.on_event(defines.events.on_player_rotated_entity, function(e)
  local ent = e.entity
  if not is_crane(ent) then return end

  -- Use the rotate key (R) as a mode toggle, not as physical rotation.
  -- Keep direction unchanged so placement checks stay consistent.
  if e.previous_direction ~= nil then
    pcall(function() ent.direction = e.previous_direction end)
  end

  apply_crane_runtime_settings(ent)
  toggle_crane_mode(ent, e.player_index)
  create_crane_visual(ent)

  if not shore_ok(ent.surface, ent.position, ent.direction) then
    invalidate_crane(ent, e.player_index, "[Port Crane] Invalid placement: must be offshore, with waterway 1 or 2 tiles from shore.")
  end
end)



local function apply_to_all_cranes()
  for _, surface in pairs(game.surfaces) do
    for name, _ in pairs(CRANE_NAMES) do
      local cranes = surface.find_entities_filtered{name = name}
      for _, ent in pairs(cranes) do
        apply_crane_runtime_settings(ent)
      end
    end
  end
end

local function refresh_all_crane_visuals()
  for _, surface in pairs(game.surfaces) do
    local cranes = surface.find_entities_filtered{name = "port-crane"}
    for _, ent in pairs(cranes) do
      create_crane_visual(ent)
    end
  end
end

script.on_init(function()
  ensure_globals()
  if game then
    apply_to_all_cranes()
    refresh_all_crane_visuals()
  end
end)

script.on_configuration_changed(function()
  ensure_globals()
  -- Re-apply runtime settings and recreate visuals after updates.
  if game then
    apply_to_all_cranes()
    refresh_all_crane_visuals()
  end
end)
