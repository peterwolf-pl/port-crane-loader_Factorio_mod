# Port Crane Loader (3x3)

Two shore cranes for Cargo Ships:
- **port-crane-loader**: moves items from land to ship (over waterway)
- **port-crane-unloader**: moves items from ship to land

## Placement rules (strict)
- The crane sits on land (3x3 collision footprint).
- In front of the crane there must be a **3x3 area** covered by **straight-waterway** (or legacy-straight-waterway).
- Curved or diagonal waterways are rejected.
- Waterway orientation must be parallel to the shore (perpendicular to crane facing).

## Custom graphics
Replace these files with your own:
- `graphics/icons/port_crane_icon.png` (64x64)
- `graphics/entity/port_crane/port_crane_platform_4dir.png` (4 directions, 384x384 each, in one row)

This mod hides the inserter hand, so the crane is a static sprite.
