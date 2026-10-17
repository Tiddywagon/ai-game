"""Writes maps/factory.tscn: the Factory gray-box map (DESIGN.md §5). Run from anywhere:
python3 tools/make_factory_map.py <project root>

North is -z. The map is 60 x 48 m inside a 5 m perimeter wall. Buildings: the main hall (centre,
with a catwalk along its north wall and the overseer's office raised on a block in its north-east
corner), the boiler house (north, dark, the Cellars extract), the office building (north-west: records,
server room, archive with the office window extract), the locker rooms (south-west: lockers, break room,
showers), the med bay and lab (north-east) and the warehouse with the armory cage (south-east).
Points of interest (DESIGN.md §5.2) mark each area, plus a floor stash in the break room, a generator
bunker in the boiler yard behind a power door, and a crashed supply truck between the med bay and the
warehouse. Iron Matvei's boss spawn (DESIGN.md §4.3) is in the boiler house.
"""
import math, sys

ROOT = sys.argv[1]

ext = []        # (type, path, id)
subs = []       # text blocks
nodes = []      # text blocks
_ids = {}


def ext_res(kind, path):
    if path in _ids:
        return _ids[path]
    rid = "%d_%s" % (len(ext) + 1, path.rsplit("/", 1)[-1].split(".")[0][:12])
    ext.append((kind, path, rid))
    _ids[path] = rid
    return rid


def sub(kind, rid, props):
    subs.append('[sub_resource type="%s" id="%s"]\n%s\n' % (kind, rid, "\n".join("%s = %s" % kv for kv in props)))
    return rid


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return ("%.4f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)
    return v


def vec3(x, y, z):
    return "Vector3(%s, %s, %s)" % (fmt(float(x)), fmt(float(y)), fmt(float(z)))


def node(name, kind, parent, props=(), instance=None):
    head = '[node name="%s"' % name
    if kind:
        head += ' type="%s"' % kind
    head += ' parent="%s"' % parent
    if instance:
        head += ' instance=ExtResource("%s")' % instance
    head += "]"
    nodes.append(head + "\n" + "".join("%s = %s\n" % (k, v) for k, v in props))


COVER = ext_res("Script", "res://scripts/world/cover_box.gd")
DOOR = ext_res("Script", "res://scripts/world/door.gd")
STAIRS = ext_res("Script", "res://scripts/world/stairs.gd")
SLAB = ext_res("Script", "res://scripts/world/floor_slab.gd")
LABEL = ext_res("Script", "res://scripts/world/map_label.gd")
POI = ext_res("Script", "res://scripts/world/point_of_interest.gd")
HATCH = ext_res("Script", "res://scripts/world/floor_hatch.gd")
SCAVZONE = ext_res("Script", "res://scripts/world/scav_zone.gd")
SPAWN = ext_res("Script", "res://scripts/world/spawn_point.gd")
BOX = ext_res("Script", "res://scripts/world/loot_box.gd")
PICKUP = ext_res("Script", "res://scripts/world/loot_pickup.gd")
EXTRACT = ext_res("Script", "res://scripts/world/extract_zone.gd")
DARK = ext_res("Script", "res://scripts/world/dark_zone.gd")
POWER = ext_res("Script", "res://scripts/world/power_switch.gd")
BOSS = ext_res("Script", "res://scripts/world/boss_spawn.gd")

WOOD, CONCRETE, METAL = 0, 1, 2
counter = {}


def uid(prefix):
    counter[prefix] = counter.get(prefix, 0) + 1
    return "%s%d" % (prefix, counter[prefix])


def rot(deg):
    return vec3(0, math.radians(deg), 0)


# --- Geometry helpers (all under Navigation/Geometry, baked for the AI) ---------------------------

GEO = "Navigation/Geometry"


def box(name, cx, cz, sx, sz, height, material=CONCRETE, y0=0.0, cover=True):
    props = [("position", vec3(cx, y0 + height / 2.0, cz)), ("script", 'ExtResource("%s")' % COVER),
             ("size", vec3(sx, height, sz)), ("cover_material", material)]
    if not cover:
        props.append(("provides_cover", "false"))
    node(name, "StaticBody3D", GEO, props)


def wall(name, x1, z1, x2, z2, height=3.5, material=CONCRETE, gaps=(), thickness=0.4, y0=0.0):
    """An axis-aligned wall from (x1, z1) to (x2, z2), with gaps: (centre along the wall, width, door
    dict or None). Doors get a Door node in the gap."""
    horizontal = abs(z2 - z1) < 1e-6
    a, b = (min(x1, x2), max(x1, x2)) if horizontal else (min(z1, z2), max(z1, z2))
    fixed = z1 if horizontal else x1
    cuts = sorted(gaps, key=lambda g: g[0])
    start = a
    pieces = []
    for centre, width, door in cuts:
        pieces.append((start, centre - width / 2.0))
        if door is not None:
            dname = door.get("name", "Door")
            props = [("position", vec3(centre if horizontal else fixed, y0, fixed if horizontal else centre)),
                     ("script", 'ExtResource("%s")' % DOOR), ("width", fmt(float(width))), ("door_name", '"%s"' % dname)]
            if not horizontal:
                props.insert(1, ("rotation", rot(90)))
            if door.get("metal"):
                props.append(("cover_material", 2))
            if door.get("back"):
                props.append(("opens_back", "true"))
            if door.get("key"):
                props += [("locked", "true"), ("key_id", '"%s"' % door["key"])]
            if door.get("power"):
                props += [("locked", "true"), ("needs_power", "true")]
            if door.get("lever"):
                props += [("locked", "true"), ("lever_id", '"%s"' % door["lever"])]
            if door.get("height"):
                props.append(("height", fmt(float(door["height"]))))
            node(uid("Door_"), "Node3D", "Doors", props)
        start = centre + width / 2.0
    pieces.append((start, b))
    for i, (p, q) in enumerate(pieces):
        # The outer ends overlap the corner by half the thickness; the ends at a gap don't.
        if i == 0:
            p -= thickness / 2.0
        if i == len(pieces) - 1:
            q += thickness / 2.0
        if q - p < 0.05:
            continue
        mid = (p + q) / 2.0
        length = q - p
        if horizontal:
            box("%s_%d" % (name, i), mid, fixed, length, thickness, height, material, y0)
        else:
            box("%s_%d" % (name, i), fixed, mid, thickness, length, height, material, y0)


def stairs(name, cx, cz, width, rise, run, toward):
    """Stairs whose top points `toward` ("north", "south", "east", "west")."""
    deg = {"south": 0, "east": 90, "north": 180, "west": -90}[toward]
    node(name, "StaticBody3D", GEO, [("position", vec3(cx, 0, cz)), ("rotation", rot(deg)),
        ("script", 'ExtResource("%s")' % STAIRS), ("size", vec3(width, rise, run))])


def slab(name, cx, cz, sx, sz, top, grating=True):
    node(name, "StaticBody3D", GEO, [("position", vec3(cx, top, cz)), ("script", 'ExtResource("%s")' % SLAB),
        ("size", vec3(sx, 0.2, sz)), ("grating", fmt(grating))])


# --- Scene skeleton ---------------------------------------------------------------------------------

LEVEL = ext_res("Script", "res://scripts/maps/raid_level.gd")
GRID = ext_res("Texture2D", "res://assets/textures/prototype_grid.png")
PLAYER = ext_res("PackedScene", "res://scenes/actors/player.tscn")
CAR = ext_res("PackedScene", "res://scenes/props/car.tscn")
CAMERA = ext_res("Script", "res://scripts/camera/top_down_camera.gd")
HUD = ext_res("PackedScene", "res://ui/hud.tscn")
PAUSE = ext_res("PackedScene", "res://ui/pause_menu.tscn")
VISION = ext_res("Script", "res://scripts/world/player_vision.gd")
ENV = ext_res("Script", "res://scripts/world/raid_environment.gd")
INVENTORY = ext_res("Script", "res://scripts/ui/inventory/inventory_layer.gd")
RAID = ext_res("Script", "res://scripts/raid/raid_controller.gd")

sub("Environment", "Environment_factory", [("background_mode", 1), ("background_color", "Color(0.09, 0.09, 0.09, 1)"),
    ("ambient_light_source", 2), ("ambient_light_color", "Color(0.75, 0.76, 0.82, 1)"), ("ambient_light_energy", 0.45), ("tonemap_mode", 2)])
sub("NavigationMesh", "NavigationMesh_factory", [("geometry_parsed_geometry_type", 1), ("geometry_collision_mask", 1),
    ("cell_size", 0.1), ("cell_height", 0.25), ("agent_height", 1.75), ("agent_radius", 0.4), ("agent_max_climb", 0.25)])
sub("BoxShape3D", "BoxShape3D_ground", [("size", vec3(64, 1, 52))])
sub("StandardMaterial3D", "Material_ground", [("albedo_color", "Color(0.5, 0.5, 0.47, 1)"), ("albedo_texture", 'ExtResource("%s")' % GRID),
    ("roughness", 0.95), ("uv1_triplanar", "true"), ("uv1_world_triplanar", "true")])
sub("BoxMesh", "BoxMesh_ground", [("material", 'SubResource("Material_ground")'), ("size", vec3(64, 1, 52))])

node("Factory", "Node3D", None)
nodes[-1] = '[node name="Factory" type="Node3D"]\nscript = ExtResource("%s")\n' % LEVEL
node("WorldEnvironment", "WorldEnvironment", ".", [("environment", 'SubResource("Environment_factory")')])
node("Sun", "DirectionalLight3D", ".", [("rotation_degrees", vec3(-72, -25, 0)), ("light_energy", 1.1), ("shadow_enabled", "true"),
    ("directional_shadow_max_distance", 70.0)])
nodes.append('[node name="RaidEnvironment" type="Node" parent="." node_paths=PackedStringArray("sun", "world_environment")]\n'
    'script = ExtResource("%s")\nsun = NodePath("../Sun")\nworld_environment = NodePath("../WorldEnvironment")\n' % ENV)
node("Navigation", "NavigationRegion3D", ".", [("navigation_mesh", 'SubResource("NavigationMesh_factory")')])
node("Ground", "StaticBody3D", "Navigation", [("position", vec3(0, -0.5, 0))])
node("CollisionShape3D", "CollisionShape3D", "Navigation/Ground", [("shape", 'SubResource("BoxShape3D_ground")')])
node("MeshInstance3D", "MeshInstance3D", "Navigation/Ground", [("mesh", 'SubResource("BoxMesh_ground")')])
node("Geometry", "Node3D", "Navigation")
node("Loot", "Node3D", "Navigation")
node_doors_index = len(nodes)  # Doors go outside the navigation region (the AI opens them).

# --- Perimeter -------------------------------------------------------------------------------------
wall("Perimeter_N", -30, -24, 30, -24, 5.0)
wall("Perimeter_W", -30, -24, -30, 24, 5.0)
wall("Perimeter_E", 30, -24, 30, 24, 5.0)
wall("Perimeter_S", -30, 24, 30, 24, 5.0, gaps=[(0, 6.0, None)])
box("Gate3_Gate", 0, 24.1, 6.0, 0.3, 4.0, METAL)  # The gate itself, shut.

# --- Main hall (centre): x -12..12, z -8..10 --------------------------------------------------------------
HALL_H = 5.0
wall("Hall_N", -12, -8, 12, -8, HALL_H, gaps=[(-8.0, 1.2, {"name": "Boiler yard door"}), (1.0, 1.2, {"name": "Hall north door"})])
wall("Hall_S", -12, 10, 12, 10, HALL_H, gaps=[(0.0, 6.0, None)])
wall("Hall_W", -12, -8, -12, 10, HALL_H, gaps=[(0.5, 3.0, None)])
wall("Hall_E", 12, -8, 12, 10, HALL_H, gaps=[(3.5, 3.0, None), (8.5, 1.2, {"name": "East yard door", "metal": True})])
# Machinery: press lines and lathes (metal), a conveyor (low), crates.
for i, (x, z) in enumerate([(-7, -3), (-7, 3.5), (-2, -3), (-2, 3.5)]):
    box("Press_%d" % i, x, z, 2.2, 2.2, 2.6, METAL)
box("Conveyor", 1.2, 0.5, 1.2, 8.0, 1.0, METAL)
box("Lathe_A", 8.5, 4.5, 2.0, 1.2, 1.4, METAL)
box("Lathe_B", 8.5, 7.5, 2.0, 1.2, 1.4, METAL)
box("Hall_Crates_A", -10.5, 8.5, 1.2, 1.2, 1.2, WOOD)
box("Hall_Crates_B", -9.2, 8.6, 1.2, 1.2, 1.2, WOOD)
box("Hall_Pallet", 6.0, 8.6, 2.0, 1.2, 0.9, WOOD)
box("Hall_Barrier", -4.5, 8.0, 3.0, 0.4, 1.0, CONCRETE)
# Catwalk along the north wall at 3 m, stairs up at its west end, a landing at its east end by the
# overseer's office (which sits on a 3 m block in the north-east corner).
slab("Catwalk", -4.15, -7.0, 15.3, 1.6, 3.0)
slab("Landing", 4.25, -6.1, 1.5, 3.4, 3.0)
stairs("Stairs_Catwalk", -10.9, -3.7, 1.4, 3.0, 5.0, "north")
stairs("Stairs_Office", 4.25, -1.9, 1.4, 3.0, 5.0, "north")
box("Railing_Catwalk", -3.35, -6.15, 13.7, 0.1, 1.0, METAL, y0=3.0)
box("Railing_Landing", 3.45, -5.3, 0.1, 1.8, 1.0, METAL, y0=3.0)
# The overseer's office: a 3 m block, an office on top (locked: the Factory office key).
box("Overseer_Block", 8.4, -4.9, 6.8, 5.8, 3.0, CONCRETE)
wall("Overseer_W", 5.1, -7.8, 5.1, -2.0, 2.4, gaps=[(-5.4, 1.1, {"name": "Overseer's office door", "key": "office_key", "height": 2.1})], thickness=0.2, y0=3.0)
wall("Overseer_S", 5.1, -2.0, 11.8, -2.0, 2.4, thickness=0.2, y0=3.0)
box("Overseer_Desk", 9.5, -5.0, 1.6, 0.8, 0.8, WOOD, y0=3.0)

# --- Boiler house (north): x -6..6, z -20..-12 ---------------------------------------------------------
wall("Boiler_S", -6, -12, 6, -12, 4.0, gaps=[(0.0, 1.4, {"name": "Boiler house door", "metal": True})])
wall("Boiler_N", -6, -20, 6, -20, 4.0)
wall("Boiler_W", -6, -20, -6, -12, 4.0)
wall("Boiler_E", 6, -20, 6, -12, 4.0, gaps=[(-16.0, 1.2, {"name": "Boiler house side door", "metal": True})])
box("Boiler_A", 2.5, -17.5, 2.6, 3.0, 3.0, METAL)
box("Boiler_B", -1.0, -17.5, 2.6, 3.0, 3.0, METAL)
box("Boiler_Pipes", 3.5, -13.5, 3.0, 0.6, 1.2, METAL)
box("Cellar_Hatch_Rim", -4.0, -16.0, 1.6, 0.2, 0.5, CONCRETE)

# --- Office building (north-west): x -28..-15, z -22..-12 -------------------------------------------------
wall("Office_S", -28, -12, -15, -12, 3.5, gaps=[(-21.0, 1.2, {"name": "Office back door", "back": True})])
wall("Office_N", -28, -22, -15, -22, 3.5, gaps=[(-25.5, 1.6, None)])  # The office window (an extract).
box("Office_Window_Bars", -25.5, -22.35, 1.6, 0.1, 1.2, METAL, y0=1.0, cover=False)
wall("Office_W", -28, -22, -28, -12, 3.5)
wall("Office_E", -15, -22, -15, -12, 3.5, gaps=[(-13.5, 1.2, {"name": "Office front door"})])
wall("Office_Corridor", -28, -15, -15, -15, 3.5, gaps=[(-25.5, 1.0, {"name": "Records room door"}), (-21.0, 1.0, {"name": "Server room door"}),
    (-17.0, 1.0, {"name": "Archive door"})], thickness=0.2)
wall("Office_Split_A", -23, -22, -23, -15, 3.5, thickness=0.2)
wall("Office_Split_B", -19, -22, -19, -15, 3.5, thickness=0.2)
box("Office_Desk_A", -26.5, -18.0, 1.6, 0.8, 0.8, WOOD)
box("Office_Desk_B", -17.0, -19.5, 1.6, 0.8, 0.8, WOOD)

# --- Locker rooms (south-west): x -28..-16, z 6..20 ----------------------------------------------------
wall("Locker_N", -28, 6, -16, 6, 3.5, gaps=[(-19.0, 1.2, {"name": "Break room door"})])
wall("Locker_S", -28, 20, -16, 20, 3.5)
wall("Locker_W", -28, 6, -28, 20, 3.5)
wall("Locker_E", -16, 6, -16, 20, 3.5, gaps=[(16.5, 1.2, {"name": "Showers door"})])
wall("Locker_Split", -22, 6, -22, 20, 3.5, gaps=[(9.5, 1.0, {"name": "Locker room door"}), (17.0, 1.0, {"name": "Locker room back door"})], thickness=0.2)
wall("Locker_BreakWall", -22, 13, -16, 13, 3.5, gaps=[(-19.0, 1.0, {"name": "Showers inner door"})], thickness=0.2)
for i, z in enumerate([8.5, 11.5, 14.5, 17.5]):
    box("Lockers_%d" % i, -27.4, z, 0.6, 2.2, 2.0, METAL)
box("Locker_Bench_A", -24.8, 10.0, 0.5, 3.0, 0.5, WOOD)
box("Locker_Bench_B", -24.8, 16.0, 0.5, 3.0, 0.5, WOOD)
box("Break_Table", -19.0, 9.8, 2.0, 1.0, 0.8, WOOD)
box("Shower_Stall_A", -17.0, 18.6, 1.4, 0.1, 2.0, CONCRETE)
box("Shower_Stall_B", -20.5, 18.6, 1.4, 0.1, 2.0, CONCRETE)

# --- Med bay and lab (north-east): x 16..28, z -20..-8 ------------------------------------------------------
wall("Med_S", 16, -8, 28, -8, 3.5, gaps=[(22.0, 1.2, {"name": "Med bay door", "back": True})])
wall("Med_N", 16, -20, 28, -20, 3.5)
wall("Med_W", 16, -20, 16, -8, 3.5, gaps=[(-11.0, 1.2, {"name": "Med bay side door"})])
wall("Med_E", 28, -20, 28, -8, 3.5)
wall("Med_Split", 16, -14, 28, -14, 3.5, gaps=[(19.0, 1.0, {"name": "Lab door", "key": "factory_lab_key", "metal": True}), (25.0, 1.0, {"name": "Chem storage door"})], thickness=0.2)
wall("Lab_Split", 22, -20, 22, -14, 3.5, thickness=0.2)
box("Med_Bed_A", 18.0, -10.0, 2.0, 0.9, 0.7, METAL)
box("Med_Bed_B", 18.0, -12.4, 2.0, 0.9, 0.7, METAL)
box("Lab_Bench", 19.0, -18.5, 3.0, 0.8, 0.9, METAL)
box("Chem_Drums", 26.6, -18.4, 1.2, 1.2, 1.1, METAL)

# --- Warehouse (south-east): x 16..28, z 0..20 ---------------------------------------------------------------
wall("Ware_N", 16, 0, 28, 0, 5.0, METAL, gaps=[(20.0, 1.2, {"name": "Warehouse north door", "metal": True})])
wall("Ware_S", 16, 20, 28, 20, 5.0, METAL, gaps=[(22.0, 6.0, None)])
wall("Ware_W", 16, 0, 16, 20, 5.0, METAL, gaps=[(5.0, 4.0, None), (15.0, 1.2, {"name": "Warehouse side door", "metal": True})])
wall("Ware_E", 28, 0, 28, 20, 5.0, METAL)
for i, z in enumerate([11.0, 15.5]):
    box("Shelves_W_%d" % i, 19.0, z, 1.0, 3.2, 2.5, METAL)
    box("Shelves_E_%d" % i, 23.5, z, 1.0, 3.2, 2.5, METAL)
box("Ware_Crates_A", 25.8, 11.5, 1.4, 1.4, 1.4, WOOD)
box("Ware_Crates_B", 25.8, 13.0, 1.4, 1.4, 1.4, WOOD)
box("Ware_Pallet", 19.5, 3.0, 2.0, 1.2, 0.9, WOOD)
# The armory cage in the north-east corner of the warehouse (open; dangerous).
wall("Cage_W", 23, 0.2, 23, 8, 2.6, METAL, gaps=[(6.6, 1.0, {"name": "Armory cage gate", "metal": True})], thickness=0.15)
wall("Cage_S", 23, 8, 28, 8, 2.6, METAL, thickness=0.15)

# --- Yards: low cover, barriers, a truck at the dock --------------------------------------------------------
for i, (x, z, sx, sz) in enumerate([(-20, -6, 3, 0.4), (-24, 0, 0.4, 3), (-16, 2, 2, 0.4), (-7, 16, 3, 0.4), (6, 15, 3, 0.4),
                                     (13.5, -14, 0.4, 3), (13.5, 14, 0.4, 3), (-12, -10, 2.5, 0.4), (8, -10.5, 2.5, 0.4)]):
    box("Barrier_%d" % i, x, z, sx, sz, 1.0, CONCRETE)
for i, (x, z) in enumerate([(-22, -3), (-9, 20), (9, 19.5), (14.2, 21)]):
    box("Yard_Crate_%d" % i, x, z, 1.2, 1.2, 1.2, WOOD)
nodes.append('[node name="Truck" parent="%s" instance=ExtResource("%s")]\nposition = %s\n' % (GEO, CAR, vec3(26.5, 0, 22.3)))
box("Water_Tower_Base", -12.0, 19.5, 1.6, 1.6, 2.0, CONCRETE)
box("Smokestack_Base", 3.0, -22.0, 2.4, 2.4, 4.0, CONCRETE)

# --- Generator bunker (boiler yard, hidden POI): concrete, its blast door runs on the factory's power ------
wall("Bunker_W", -14, -23.8, -14, -19.5, 3.0, thickness=0.5)
wall("Bunker_E", -8.5, -23.8, -8.5, -19.5, 3.0, thickness=0.5)
wall("Bunker_S", -14, -19.5, -8.5, -19.5, 3.0, gaps=[(-11.25, 1.2, {"name": "Bunker blast door", "metal": True, "power": True})], thickness=0.5)
box("Bunker_Generator", -10.0, -22.6, 1.4, 1.2, 1.4, METAL)

# --- Crashed supply truck (east lane between the med bay and the warehouse) ----------------------------------
nodes.append('[node name="CrashedTruck" parent="%s" instance=ExtResource("%s")]\nposition = %s\nrotation = %s\n' % (GEO, CAR,
    vec3(24.5, 0.12, -3.6), vec3(math.radians(-4), math.radians(20), math.radians(7))))

# --- Landmark visuals (no collision): smokestack, crane, water tank -------------------------------------
def mesh(name, mesh_kind, size_props, color, pos, parent="Landmarks", emissive=False):
    mid = "Mesh_%s" % name
    matid = "Mat_%s" % name
    props = [("albedo_color", color), ("roughness", 0.8)]
    if emissive:
        props += [("emission_enabled", "true"), ("emission", color)]
    sub("StandardMaterial3D", matid, props)
    sub(mesh_kind, mid, [("material", 'SubResource("%s")' % matid)] + size_props)
    node(name, "MeshInstance3D", parent, [("position", pos), ("mesh", 'SubResource("%s")' % mid)])

node("Landmarks", "Node3D", ".")
mesh("Smokestack", "CylinderMesh", [("top_radius", 0.9), ("bottom_radius", 1.1), ("height", 16.0)], "Color(0.7, 0.18, 0.14, 1)", vec3(3.0, 8.0, -22.0))
mesh("Smokestack_Band", "CylinderMesh", [("top_radius", 0.95), ("bottom_radius", 0.95), ("height", 1.0)], "Color(0.92, 0.92, 0.9, 1)", vec3(3.0, 13.5, -22.0))
mesh("Crane_Beam", "BoxMesh", [("size", vec3(24.0, 0.5, 0.6))], "Color(0.95, 0.75, 0.1, 1)", vec3(0.0, 6.6, 1.5))
mesh("Crane_Hook", "BoxMesh", [("size", vec3(0.8, 1.2, 0.8))], "Color(0.95, 0.75, 0.1, 1)", vec3(-3.0, 5.6, 1.5))
mesh("Crane_Rail_W", "BoxMesh", [("size", vec3(0.4, 0.4, 18.0))], "Color(0.6, 0.5, 0.15, 1)", vec3(-11.6, 6.2, 1.0))
mesh("Crane_Rail_E", "BoxMesh", [("size", vec3(0.4, 0.4, 18.0))], "Color(0.6, 0.5, 0.15, 1)", vec3(11.6, 6.2, 1.0))
mesh("Water_Tank", "CylinderMesh", [("top_radius", 1.8), ("bottom_radius", 1.8), ("height", 2.6)], "Color(0.25, 0.45, 0.75, 1)", vec3(-12.0, 3.4, 19.5))
mesh("Exit_Lamp_Gate3", "BoxMesh", [("size", vec3(0.6, 0.3, 0.3))], "Color(0.3, 1.0, 0.4, 1)", vec3(0.0, 4.4, 23.7), emissive=True)

# --- Doors container (filled by wall()) ----------------------------------------------------------------
nodes.insert(node_doors_index, '[node name="Doors" type="Node3D" parent="."]\n')

# --- Dark boiler house -----------------------------------------------------------------------------------
node("BoilerDark", "Node3D", ".", [("position", vec3(0, 2.0, -16.0)), ("script", 'ExtResource("%s")' % DARK), ("size", vec3(12, 4, 8))])

# --- Map labels (painted on the floor) and landmarks ---------------------------------------------------
def label(text, x, z, y=0.0, size=64, painted=True, landmark=False):
    props = [("position", vec3(x, y, z)), ("script", 'ExtResource("%s")' % LABEL), ("text", '"%s"' % text), ("paint_size", size)]
    if not painted:
        props.append(("painted", "false"))
    if landmark:
        props.append(("landmark", "true"))
    node(uid("Label_"), "Marker3D", "MapLabels", props)

node("MapLabels", "Node3D", ".")
label("Main hall", -1.0, 6.2, size=100)
label("Boiler house", 0.0, -14.5, size=60)
label("Offices", -21.5, -13.5, size=56)
label("Records", -25.5, -19.0, size=40)
label("Server room", -21.0, -19.5, size=36)
label("Archive", -17.0, -17.0, size=40)
label("Lockers", -25.0, 13.0, size=56)
label("Break room", -19.0, 7.5, size=40)
label("Showers", -19.0, 16.0, size=40)
label("Med bay", 22.0, -11.0, size=60)
label("Lab", 19.0, -16.5, size=56)
label("Chem storage", 25.0, -17.0, size=36)
label("Warehouse", 21.0, 9.0, size=80)
label("Armory", 25.5, 4.0, size=48)
label("Gate 3", 0.0, 21.5, size=90)
label("Loading dock", 22.0, 22.3, size=56)
label("Overseer", 8.4, -4.0, y=3.02, size=48)
label("West yard", -22.0, 1.5, size=56)
label("East yard", 14.0, -2.0, size=40)
label("Smokestack", 3.0, -22.0, painted=False, landmark=True)
label("Crane", 0.0, 1.5, painted=False, landmark=True)
label("Water tower", -12.0, 19.5, painted=False, landmark=True)

# --- Points of interest (DESIGN.md §5.2): the rules are the Factory rows of data/config/pois.json ---------
# Each is a box (centre x, base y, centre z; size); the containers and loose spots in it are its spawn
# points. Event spots (airdrop, truck, cache) are where raid events can happen at it.
def poi(poi_id, x, y, z, sx, sy, sz, events=()):
    name = "POI_" + poi_id
    node(name, "Node3D", "POIs", [("position", vec3(x, y, z)), ("script", 'ExtResource("%s")' % POI), ("map_id", '"factory"'),
        ("poi_id", '"%s"' % poi_id), ("size", vec3(sx, sy, sz))])
    for kind, ex, ez in events:
        node("EventSpot_" + kind, "Marker3D", "POIs/" + name, [("position", vec3(ex - x, -y, ez - z))])

node("POIs", "Node3D", ".")
poi("main_hall", 0.0, 0.0, 1.0, 24.0, 6.5, 18.0, events=[("airdrop", -4.5, 0.25)])
poi("overseers_office", 8.4, 3.0, -4.9, 6.6, 3.0, 5.6)
poi("boiler_house", 0.0, 0.0, -16.0, 12.0, 4.0, 8.0, events=[("cache", 0.5, -14.2)])
poi("offices", -21.5, 0.0, -17.0, 13.0, 3.5, 10.0)
poi("locker_rooms", -22.0, 0.0, 13.0, 12.0, 3.5, 14.0)
poi("med_bay", 22.0, 0.0, -14.0, 12.0, 3.5, 12.0)
poi("lab", 19.0, 0.0, -17.0, 6.0, 3.5, 6.0)
poi("warehouse", 22.0, 0.0, 10.0, 12.0, 5.0, 20.0, events=[("truck", 8.5, 22.0)])
poi("armory_cage", 25.5, 0.0, 4.0, 5.0, 3.0, 7.6, events=[("cache", 24.6, 4.8)])
poi("foremans_stash", -18.6, 0.0, 12.0, 2.0, 2.0, 2.0)
poi("generator_bunker", -11.25, 0.0, -21.65, 5.5, 3.0, 4.3)
poi("crashed_truck", 23.5, 0.0, -4.0, 9.0, 3.0, 7.0, events=[("airdrop", 19.0, -4.5)])

# --- Scav zones (AI Scavs spawn and patrol), then spawn points, then the player and the raid ----------
def scav_zone(name, count, points):
    zone_path = name
    node(name, "Node3D", ".", [("script", 'ExtResource("%s")' % SCAVZONE), ("zone_name", '"%s"' % name.replace("_", " ")), ("count", count)])
    for i, (x, z) in enumerate(points):
        node("P%d" % (i + 1), "Marker3D", zone_path, [("position", vec3(x, 0, z))])

scav_zone("Main_hall", 3, [(-5, 0.5), (0.5, -5), (6, 2), (-1, 7), (9, 6), (-9.5, -1)])
scav_zone("Warehouse", 3, [(18.5, 4), (21.5, 8), (21.0, 13.5), (25.8, 16.5), (18, 18)])
scav_zone("Locker_rooms", 2, [(-25.8, 9), (-19, 11), (-19, 16.5), (-25.8, 18.2)])

# Iron Matvei, the Furnace King (data/config/bosses.json) holds the boiler house, 35% of raids: he stands
# by the door, his Stokers at the haunt points, and he wanders between them.
node("BossSpawn", "Node3D", ".", [("position", vec3(0.0, 0, -14.4)), ("script", 'ExtResource("%s")' % BOSS), ("map_id", '"factory"')])
for i, (x, z) in enumerate([(-4.0, -14.0), (4.6, -15.4), (-4.4, -19.0), (1.0, -14.2)]):
    node("Haunt%d" % (i + 1), "Marker3D", "BossSpawn", [("position", vec3(x, 0, z + 14.4))])

node("SpawnPoints", "Node3D", ".")
for name, side, (x, z), deg in [("WestYard", "PMC", (-24, -6), 90), ("SouthWest", "PMC", (-15, 22), 180), ("NorthEastYard", "PMC", (14, -21), 0),
                                ("LoadingDock", "PMC", (21, 22.6), 180), ("BoilerYard", "PMC", (-9, -10), 0), ("EastYard", "PMC", (14, 9), -90),
                                ("ScavHall", "Scav", (-3, 9), 180), ("ScavWarehouse", "Scav", (21, 17.5), 180), ("ScavLockers", "Scav", (-19, 11.5), 180)]:
    node(name, "Marker3D", "SpawnPoints", [("position", vec3(x, 0, z)), ("rotation", rot(deg)), ("script", 'ExtResource("%s")' % SPAWN), ("side", '"%s"' % side)])

node("Player", None, ".", [("position", vec3(-24, 0, -6))], instance=PLAYER)
nodes.append('[node name="Raid" type="Node" parent="." node_paths=PackedStringArray("player")]\nscript = ExtResource("%s")\nplayer = NodePath("../Player")\nmap_id = "factory"\nai_pmcs = 3\n' % RAID)

# --- Extracts --------------------------------------------------------------------------------------------
def extract(name, x, z, radius, **props):
    p = [("position", vec3(x, 0, z)), ("script", 'ExtResource("%s")' % EXTRACT), ("extract_name", '"%s"' % props.pop("title")), ("radius", fmt(float(radius)))]
    for k, v in props.items():
        p.append((k, '"%s"' % v if isinstance(v, str) else fmt(v)))
    node(name, "Area3D", ".", p)

# The rules (always open, random, key and power) are the Factory row of data/config/extracts.json.
extract("ExtractGate3", 0.0, 22.2, 2.2, title="Gate 3", extract_id="gate_3")
extract("ExtractCellars", -4.0, -17.8, 1.4, title="Cellars", extract_id="cellars")
extract("ExtractOfficeWindow", -25.5, -21.0, 1.1, title="Office window", extract_id="office_window")
# The Cellars need the power on: the switch is on the boiler house's east wall.
node("PowerSwitch", "Node3D", ".", [("position", vec3(5.65, 0.0, -14.6)), ("rotation", "Vector3(0, %s, 0)" % fmt(math.radians(90))),
    ("script", 'ExtResource("%s")' % POWER), ("switch_name", '"Boiler house power switch"')])

# --- Containers --------------------------------------------------------------------------------------------
def container(kind, x, z, facing, y=0.0, name=None):
    """facing: the way its front looks: north, south, east or west."""
    deg = {"north": 0, "south": 180, "east": -90, "west": 90}[facing]
    rid = ext_res("Resource", "res://data/loot_tables/containers/%s.tres" % kind)
    node(name or uid("Box_" + kind + "_"), "Node3D", "Navigation/Loot", [("position", vec3(x, y, z)), ("rotation", rot(deg)),
        ("script", 'ExtResource("%s")' % BOX), ("container", 'ExtResource("%s")' % rid)])

# Main hall
container("toolbox", -5.6, -3.0, "east")
container("toolbox", 7.2, 6.0, "south")
container("crate", -10.8, 6.5, "east")
container("crate", 10.8, -1.0, "west")
container("crate", 1.5, 8.6, "north")
container("duffle_bag", -2.0, 0.3, "south")
container("jacket", 4.0, -6.9, "south", y=3.0)  # Hung on the catwalk.
# Overseer's office (high-value)
container("safe", 11.4, -7.3, "west", y=3.0)
container("filing_cabinet", 6.0, -7.4, "south", y=3.0)
container("pc", 9.5, -6.1, "south", y=3.0)
container("drawer", 11.5, -3.5, "west", y=3.0)
# Boiler house
container("toolbox", 5.3, -18.6, "west")
container("crate", -5.2, -13.0, "east")
container("pc", -5.5, -19.4, "east")
# Office building
container("filing_cabinet", -27.4, -21.3, "east")
container("filing_cabinet", -27.4, -16.5, "east")
container("drawer", -23.4, -20.6, "west")
container("server_rack", -22.4, -21.3, "east")
container("server_rack", -19.65, -21.3, "west")
container("pc", -22.4, -16.0, "north")
container("filing_cabinet", -15.6, -21.3, "west")
container("drawer", -18.6, -17.0, "east")
container("jacket", -27.0, -12.8, "north")
# Locker rooms
container("jacket", -26.8, 8.5, "east")
container("jacket", -26.8, 14.5, "east")
container("jacket", -26.8, 17.5, "east")
container("drawer", -23.0, 19.4, "north")
container("drawer", -22.4, 7.2, "west")
container("fridge", -16.7, 7.0, "west")
container("kitchen_cabinet", -21.3, 12.5, "north")
container("store_shelf", -16.8, 11.5, "west")
container("medicine_cabinet", -21.5, 14.0, "east")
# Med bay and lab
container("medicine_cabinet", 27.6, -9.0, "west")
container("medicine_cabinet", 27.6, -12.5, "west")
container("medical_crate", 20.5, -8.6, "north")
container("medical_bag", 24.5, -11.0, "south")
container("lab_cabinet", 16.6, -19.2, "east")
container("lab_cabinet", 21.6, -19.2, "west")
container("pc", 20.2, -14.4, "north")
container("crate", 27.4, -15.0, "west")
container("duffle_bag", 24.0, -19.0, "south")
# Warehouse and armory cage
container("crate", 19.0, 13.2, "south")
container("crate", 23.5, 9.0, "north")
container("crate", 26.8, 18.8, "west")
container("duffle_bag", 17.0, 18.6, "east")
container("duffle_bag", 26.0, 10.0, "west")
container("toolbox", 21.0, 1.0, "south")
container("weapon_box", 27.2, 2.0, "west")
container("weapon_box", 27.2, 5.0, "west")
container("weapon_box", 24.2, 1.0, "south")
container("crate", 26.8, 7.2, "north")
# Generator bunker
container("weapon_box", -12.6, -23.1, "south")
container("crate", -9.3, -21.0, "west")
# Crashed supply truck
container("crate", 21.6, -2.4, "east")
container("medical_bag", 27.2, -6.2, "west")
container("duffle_bag", 22.6, -5.8, "north")
# Yards
container("crate", -20.5, -3.0, "east")
container("duffle_bag", 13.0, 18.5, "west")
container("crate", -29.0, 3.0, "east")

# --- Loose loot ------------------------------------------------------------------------------------------
for i, (x, z, y) in enumerate([(-8.0, 0.5, 0), (2.5, -1.0, 0), (10.0, 2.0, 0), (-1.0, -7.0, 3.0), (0.5, -15.0, 0), (-4.0, -13.5, 0),
                               (-27.2, -13.5, 0), (-17.5, -20.0, 0), (-24.5, 12.0, 0), (-18.0, 18.0, 0), (19.0, -11.5, 0),
                               (19.0, -16.0, 0), (25.0, -16.0, 0), (21.0, 6.0, 0), (25.0, 3.0, 0), (21.0, 17.0, 0), (-14.0, -4.0, 0),
                               (14.0, -10.0, 0), (6.0, 18.0, 0), (8.0, -6.0, 3.0)]):
    node(uid("Loose_"), "Node3D", "Navigation/Loot", [("position", vec3(x, y, z)), ("script", 'ExtResource("%s")' % PICKUP), ("spawn_chance", 0.65)])
# Loose spots in the new POIs.
for x, z in [(-11.2, -21.0), (25.6, -1.2)]:
    node(uid("Loose_"), "Node3D", "Navigation/Loot", [("position", vec3(x, 0, z)), ("script", 'ExtResource("%s")' % PICKUP), ("spawn_chance", 0.65)])
# The foreman's floor stash in the break room: loose boards over a hidden container.
node("ForemanHatch", "Node3D", "Navigation/Loot", [("position", vec3(-18.6, 0, 12.0)), ("script", 'ExtResource("%s")' % HATCH),
    ("hatch_name", '"Loose floor panel"')])
rid = ext_res("Resource", "res://data/loot_tables/containers/floor_stash.tres")
node("Stash", "Node3D", "Navigation/Loot/ForemanHatch", [("position", vec3(0, 0, 0)), ("script", 'ExtResource("%s")' % BOX),
    ("container", 'ExtResource("%s")' % rid), ("concealed", "true")])
# A map of the factory on the guard's desk, and the exit key, sometimes.
node("Loose_Map", "Node3D", "Navigation/Loot", [("position", vec3(-26.5, 0.85, -18.0)), ("script", 'ExtResource("%s")' % PICKUP), ("item_id", '"factory_map"'),
    ("spawn_chance", 0.5)])

# --- Camera, UI, vision ------------------------------------------------------------------------------------
nodes.append('[node name="Camera3D" type="Camera3D" parent="." node_paths=PackedStringArray("target")]\nfov = 55.0\ncurrent = true\nscript = ExtResource("%s")\ntarget = NodePath("../Player")\n' % CAMERA)
nodes.append('[node name="HUD" parent="." node_paths=PackedStringArray("player") instance=ExtResource("%s")]\nplayer = NodePath("../Player")\n' % HUD)
nodes.append('[node name="InventoryLayer" type="CanvasLayer" parent="." node_paths=PackedStringArray("player")]\nscript = ExtResource("%s")\nplayer = NodePath("../Player")\n' % INVENTORY)
nodes.append('[node name="PlayerVision" type="Node" parent="." node_paths=PackedStringArray("player")]\nscript = ExtResource("%s")\nplayer = NodePath("../Player")\n' % VISION)
nodes.append('[node name="PauseMenu" parent="." instance=ExtResource("%s")]\n' % PAUSE)

out = ["[gd_scene format=3]\n"]
for kind, path, rid in ext:
    out.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
out.append("")
out += subs
out += nodes
open(ROOT + "/maps/factory.tscn", "w").write("\n".join(out))
print("nodes:", len(nodes), "doors:", counter.get("Door_", 0))
