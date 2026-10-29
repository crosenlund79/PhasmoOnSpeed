#!/usr/bin/env python3
"""Authoring tool for SPECTRAL RUN houses.

Houses are described as room rectangles, door cells and furniture. This script
writes data/houses/<id>.json (the format the game loads) and, with --preview,
renders floorplan previews so layouts can be checked by eye.

Grid rules (mirrored by scripts/world/house_map.gd):
  * every room rect lists interior cells; rects of the same room may touch
  * an empty cell next to (8-neighbourhood) any room cell becomes a wall
  * door cells must be wall cells; they become walkable openings
  * furniture: [type, x, y, rot] where (x, y) is the top-left cell of the
    rotated footprint and rot is 0..3 quarter turns (0 = front faces down)

Usage: python3 tools/houses/build_houses.py [--preview OUT_DIR]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def room(rid, name, floor, kind, rects, lit=True, outdoor=False):
    return {"id": rid, "name": name, "floor": floor, "kind": kind, "lit": lit,
            "outdoor": outdoor, "rects": rects}


HOUSES = []

# ---------------------------------------------------------------------------
# 1. Ashgrove Cottage — compact, a long central hallway with loops on all sides.
HOUSES.append({
    "id": "ashgrove", "name": "Ashgrove Cottage",
    "blurb": "A widow's cottage at the edge of the moor. The kettle is still warm.",
    "size": [44, 30], "spawn": [11, 26], "npcs": 2,
    "rooms": [
        room("back_garden", "Back Garden", "grass", "yard", [[1, 1, 16, 5], [27, 1, 16, 5], [17, 5, 10, 1]], lit=False, outdoor=True),
        room("shed", "Garden Shed", "dirt", "shed", [[18, 1, 8, 3]], lit=False),
        room("west_path", "West Path", "gravel", "yard", [[1, 6, 3, 19]], lit=False, outdoor=True),
        room("east_path", "East Path", "gravel", "yard", [[40, 6, 3, 19]], lit=False, outdoor=True),
        room("front_garden", "Front Garden", "grass", "yard", [[1, 25, 42, 4]], lit=False, outdoor=True),
        room("kitchen", "Kitchen", "tile_checker", "kitchen", [[5, 7, 9, 6]]),
        room("dining", "Dining Room", "parquet", "dining", [[15, 7, 11, 6]]),
        room("study", "Study", "wood_dark", "study", [[27, 7, 12, 6]], lit=False),
        room("hallway", "Hallway", "wood_dark", "hall", [[5, 14, 34, 3]]),
        room("living", "Living Room", "carpet_red", "living", [[5, 18, 12, 6]]),
        room("bathroom", "Bathroom", "tile_white", "bathroom", [[18, 18, 5, 6]], lit=False),
        room("master", "Master Bedroom", "carpet_blue", "bedroom", [[24, 18, 8, 6]], lit=False),
        room("guest", "Guest Bedroom", "wood_light", "bedroom", [[33, 18, 6, 6]]),
    ],
    "doors": [[9, 6], [14, 10], [26, 10], [9, 13], [20, 13], [33, 13], [4, 15], [39, 9], [39, 15],
              [10, 17], [20, 17], [28, 17], [35, 17], [17, 21], [32, 21], [11, 24], [39, 19],
              [21, 4], [17, 2]],
    "furniture": [
        # kitchen
        ["stove", 5, 7, 0], ["counter", 7, 7, 0], ["sink_kitchen", 11, 7, 0], ["icebox", 13, 7, 0],
        ["counter", 7, 9, 0], ["counter", 9, 9, 0], ["barrel", 5, 12, 0], ["chair", 12, 11, 0],
        # dining
        ["rug_rect", 18, 8, 0], ["dining_table", 18, 8, 0], ["candelabra", 15, 7, 0], ["candelabra", 25, 7, 0],
        ["cabinet", 16, 12, 0], ["grandfather_clock", 25, 12, 0],
        # study
        ["bookshelf", 27, 7, 0], ["bookshelf", 30, 7, 0], ["desk", 34, 8, 0], ["chair", 35, 10, 2],
        ["armchair", 28, 10, 0], ["side_table", 30, 11, 0], ["floor_lamp", 38, 12, 0],
        # hallway
        ["rug_rect", 11, 14, 0], ["rug_rect", 25, 14, 0], ["grandfather_clock", 5, 14, 0],
        ["wall_mirror", 15, 14, 0], ["side_table", 24, 16, 0], ["potted_plant", 31, 16, 0], ["potted_plant", 38, 14, 0],
        # living
        ["fireplace", 5, 18, 0], ["rug_round", 8, 19, 0], ["sofa", 5, 20, 1], ["coffee_table", 8, 21, 0],
        ["armchair", 13, 19, 0], ["piano", 13, 22, 0], ["candelabra", 16, 18, 0],
        # bathroom
        ["bathtub", 21, 21, 0], ["toilet", 18, 23, 0], ["washbasin", 22, 18, 0], ["wall_mirror", 22, 19, 1],
        # master bedroom
        ["bed_double", 26, 20, 2], ["nightstand", 25, 23, 0], ["nightstand", 29, 23, 0],
        ["wardrobe", 24, 18, 0], ["dresser", 30, 18, 0],
        # guest bedroom
        ["bed_single", 37, 20, 2], ["nightstand", 36, 23, 0], ["dresser", 33, 23, 0], ["wall_mirror", 36, 18, 0],
        # shed
        ["workbench", 19, 1, 0], ["woodpile", 22, 1, 0], ["crates", 24, 1, 0], ["barrel", 18, 1, 0],
        # gardens
        ["tree", 3, 1, 0], ["tree", 36, 1, 0], ["hedge", 11, 2, 0], ["wash_tub", 30, 2, 0], ["barrel", 41, 7, 0],
        ["tree", 2, 25, 0], ["tree", 38, 25, 0], ["hedge", 15, 27, 0], ["hedge", 26, 27, 0], ["gravestone", 33, 27, 0],
    ],
})

# ---------------------------------------------------------------------------
# 2. Blackwood Manor — large, symmetric wings around a grand foyer, servants' loop.
HOUSES.append({
    "id": "blackwood", "name": "Blackwood Manor",
    "blurb": "Forty rooms, one family portrait, and every eye in it follows you.",
    "size": [52, 36], "spawn": [25, 32], "npcs": 3,
    "rooms": [
        room("drive", "Carriage Drive", "gravel", "yard", [[1, 30, 50, 5]], lit=False, outdoor=True),
        room("west_lawn", "West Lawn", "grass", "yard", [[1, 1, 3, 29]], lit=False, outdoor=True),
        room("east_lawn", "East Lawn", "grass", "yard", [[48, 1, 3, 29]], lit=False, outdoor=True),
        room("foyer", "Grand Foyer", "stone", "hall", [[20, 20, 12, 9]]),
        room("gallery", "Portrait Gallery", "carpet_red", "hall", [[20, 12, 12, 7]], lit=False),
        room("ballroom", "Ballroom", "parquet", "living", [[5, 20, 14, 9]]),
        room("library", "Library", "wood_dark", "study", [[33, 20, 14, 9]], lit=False),
        room("dining", "Dining Hall", "parquet", "dining", [[5, 12, 14, 7]]),
        room("conservatory", "Conservatory", "tile_white", "living", [[33, 12, 14, 7]], lit=False),
        room("kitchen", "Kitchen", "tile_checker", "kitchen", [[5, 5, 9, 6]]),
        room("pantry", "Pantry", "stone", "pantry", [[15, 5, 4, 6]], lit=False),
        room("servants_hall", "Servants' Corridor", "wood_light", "hall", [[5, 1, 42, 3]], lit=False),
        room("master", "Master Bedroom", "carpet_blue", "bedroom", [[20, 5, 12, 6]], lit=False),
        room("bathroom", "Bathroom", "tile_white", "bathroom", [[33, 5, 5, 6]]),
        room("nursery", "Nursery", "carpet_green", "bedroom", [[39, 5, 8, 6]], lit=False),
    ],
    "doors": [
        # outside access
        [25, 29], [26, 29], [4, 24], [47, 24], [4, 2], [47, 2], [4, 15], [47, 15],
        # foyer hub
        [19, 24], [32, 24], [25, 19], [26, 19],
        # gallery
        [19, 15], [32, 15], [25, 11],
        # west wing
        [12, 19], [9, 11], [14, 8], [17, 11], [10, 4], [17, 4],
        # east wing
        [40, 19], [35, 11], [43, 11], [38, 8], [35, 4], [43, 4], [28, 4],
    ],
    "furniture": [
        # foyer
        ["rug_round", 24, 22, 0], ["candelabra", 20, 20, 0], ["candelabra", 31, 20, 0], ["potted_plant", 20, 28, 0],
        ["potted_plant", 31, 28, 0], ["grandfather_clock", 22, 20, 0], ["side_table", 29, 20, 0],
        # gallery
        ["rug_rect", 23, 14, 0], ["wall_mirror", 21, 12, 0], ["wall_mirror", 29, 12, 0], ["pew", 21, 17, 0],
        ["pew", 27, 17, 0], ["floor_lamp", 31, 18, 0],
        # ballroom
        ["piano", 6, 21, 0], ["rug_round", 11, 23, 0], ["candelabra", 5, 28, 0], ["candelabra", 18, 28, 0],
        ["armchair", 16, 21, 0], ["armchair", 6, 26, 0], ["fireplace", 13, 20, 0],
        # library
        ["bookshelf", 33, 20, 0], ["bookshelf", 36, 20, 0], ["bookshelf", 42, 20, 0], ["bookshelf", 33, 28, 0],
        ["bookshelf", 37, 28, 0], ["bookshelf", 41, 28, 0], ["desk", 38, 23, 0], ["chair", 39, 25, 2],
        ["armchair", 44, 23, 0], ["floor_lamp", 46, 26, 0], ["rug_rect", 37, 22, 0],
        # dining hall
        ["rug_rect", 9, 14, 0], ["dining_table", 9, 14, 0], ["candelabra", 5, 12, 0], ["candelabra", 18, 12, 0],
        ["cabinet", 5, 18, 0], ["cabinet", 16, 18, 0], ["grandfather_clock", 18, 16, 0],
        # conservatory
        ["potted_plant", 33, 12, 0], ["potted_plant", 34, 12, 0], ["potted_plant", 46, 12, 0], ["potted_plant", 46, 18, 0],
        ["potted_plant", 33, 18, 0], ["tree", 38, 13, 0], ["armchair", 43, 13, 0], ["side_table", 42, 16, 0],
        ["wash_tub", 44, 16, 0],
        # kitchen
        ["stove", 5, 5, 0], ["stove", 7, 5, 0], ["counter", 11, 5, 0], ["sink_kitchen", 5, 10, 2],
        ["counter", 7, 7, 0], ["counter", 9, 7, 0], ["icebox", 13, 10, 0], ["barrel", 13, 5, 0],
        # pantry
        ["crates", 15, 5, 0], ["barrel", 18, 5, 0], ["barrel", 18, 10, 0], ["cabinet", 15, 10, 0],
        # servants' corridor
        ["crates", 22, 1, 0], ["barrel", 30, 3, 0], ["woodpile", 38, 1, 0], ["trunk", 13, 1, 0],
        # master bedroom
        ["bed_double", 24, 5, 0], ["nightstand", 23, 5, 0], ["nightstand", 27, 5, 0], ["wardrobe", 20, 10, 2],
        ["dresser", 30, 10, 2], ["armchair", 29, 5, 0], ["rug_rect", 23, 7, 0], ["candelabra", 31, 8, 0],
        # bathroom
        ["bathtub", 35, 7, 0], ["toilet", 33, 5, 0], ["washbasin", 37, 5, 0], ["wall_mirror", 33, 9, 3],
        # nursery
        ["bed_single", 45, 5, 0], ["trunk", 39, 10, 2], ["rug_round", 40, 6, 0], ["chair", 42, 6, 0],
        ["dresser", 45, 10, 2], ["side_table", 39, 5, 0],
        # outside
        ["tree", 1, 6, 0], ["tree", 1, 18, 0], ["tree", 48, 6, 0], ["tree", 48, 18, 0], ["hedge", 8, 32, 0],
        ["hedge", 12, 32, 0], ["hedge", 38, 32, 0], ["hedge", 42, 32, 0], ["gravestone", 2, 27, 0],
        ["gravestone", 49, 27, 0], ["tree", 17, 31, 0], ["tree", 32, 31, 0],
    ],
})

# ---------------------------------------------------------------------------
# 3. Hollow Lane Farmhouse — wraparound porch, barn and root cellar.
HOUSES.append({
    "id": "hollow_lane", "name": "Hollow Lane Farmhouse",
    "blurb": "The livestock left first. Nobody asks where to.",
    "size": [48, 32], "spawn": [14, 29], "npcs": 3,
    "rooms": [
        room("yard", "Farmyard", "dirt", "yard", [[1, 27, 46, 4]], lit=False, outdoor=True),
        room("porch", "Wraparound Porch", "wood_light", "yard", [[1, 1, 3, 26], [4, 1, 22, 2]], lit=False, outdoor=True),
        room("field", "Back Field", "grass", "yard", [[26, 1, 21, 2], [44, 3, 3, 24]], lit=False, outdoor=True),
        room("parlor", "Parlor", "carpet_green", "living", [[5, 18, 10, 8]]),
        room("kitchen", "Farm Kitchen", "wood_light", "kitchen", [[16, 18, 9, 8]]),
        room("mudroom", "Mudroom", "stone", "hall", [[26, 18, 5, 8]], lit=False),
        room("corridor", "Corridor", "wood_dark", "hall", [[5, 14, 26, 3]]),
        room("bedroom", "Bedroom", "wood_light", "bedroom", [[5, 4, 9, 9]], lit=False),
        room("kids_room", "Children's Room", "carpet_blue", "bedroom", [[15, 4, 7, 9]], lit=False),
        room("bathroom", "Washroom", "tile_white", "bathroom", [[23, 4, 8, 4]]),
        room("cellar", "Root Cellar", "stone", "cellar", [[23, 9, 8, 4]], lit=False),
        room("barn", "Barn", "dirt", "shed", [[32, 4, 11, 22]], lit=False),
    ],
    "doors": [
        [7, 26], [20, 26], [28, 26], [37, 26], [4, 20], [4, 9], [4, 15], [12, 3], [18, 3], [27, 3],
        [36, 3], [43, 12], [43, 20],
        [15, 21], [25, 23], [10, 17], [20, 17], [28, 17], [10, 13], [18, 13], [27, 13], [27, 8],
        [31, 15], [31, 23], [14, 8],
    ],
    "furniture": [
        # parlor
        ["fireplace", 6, 18, 0], ["rug_round", 8, 20, 0], ["armchair", 5, 21, 0], ["sofa", 9, 24, 2],
        ["candelabra", 14, 18, 0], ["side_table", 13, 23, 0], ["wall_mirror", 5, 24, 1],
        # kitchen
        ["stove", 16, 18, 0], ["counter", 18, 18, 0], ["sink_kitchen", 22, 18, 0], ["icebox", 24, 18, 0],
        ["dining_table", 18, 21, 0], ["barrel", 16, 25, 0], ["cabinet", 23, 25, 0],
        # mudroom
        ["trunk", 29, 21, 0], ["wash_tub", 26, 24, 0], ["barrel", 30, 25, 0],
        # corridor
        ["rug_rect", 13, 14, 0], ["grandfather_clock", 5, 14, 0], ["side_table", 23, 16, 0], ["potted_plant", 30, 14, 0],
        # bedroom
        ["bed_double", 7, 4, 0], ["nightstand", 6, 4, 0], ["nightstand", 10, 4, 0], ["wardrobe", 5, 12, 2],
        ["dresser", 11, 12, 2], ["rug_rect", 7, 8, 0],
        # children's room
        ["bed_single", 15, 4, 0], ["bed_single", 20, 4, 0], ["trunk", 19, 12, 2], ["chair", 15, 10, 0],
        ["rug_round", 16, 6, 0],
        # washroom
        ["bathtub", 23, 4, 1], ["toilet", 30, 4, 0], ["washbasin", 29, 4, 0], ["wall_mirror", 28, 7, 2],
        # root cellar
        ["barrel", 23, 9, 0], ["barrel", 24, 9, 0], ["crates", 29, 9, 0], ["cabinet", 23, 12, 2], ["woodpile", 29, 12, 0],
        # barn
        ["hay", 32, 4, 0], ["hay", 34, 4, 0], ["hay", 41, 4, 0], ["workbench", 32, 25, 2], ["woodpile", 40, 25, 0],
        ["crates", 41, 16, 0], ["hay", 32, 17, 0], ["barrel", 37, 10, 0], ["barrel", 37, 18, 0], ["crates", 34, 11, 0],
        # outside
        ["tree", 43, 28, 0], ["barrel", 2, 28, 0], ["wash_tub", 6, 29, 0], ["hay", 24, 28, 0], ["tree", 44, 4, 0],
        ["hedge", 30, 1, 0], ["gravestone", 45, 9, 0],
    ],
})

# ---------------------------------------------------------------------------
# 4. St. Evangeline Rectory — nave, crypt, vestry, rectory rooms and graveyard.
HOUSES.append({
    "id": "evangeline", "name": "St. Evangeline Rectory",
    "blurb": "Consecrated ground. Allegedly.",
    "size": [48, 34], "spawn": [22, 31], "npcs": 2,
    "rooms": [
        room("graveyard", "Graveyard", "grass", "yard", [[1, 29, 46, 4], [1, 1, 3, 28], [44, 1, 3, 28]], lit=False, outdoor=True),
        room("cloister", "Cloister Walk", "stone", "yard", [[4, 1, 40, 2]], lit=False, outdoor=True),
        room("nave", "Nave", "stone", "chapel", [[16, 13, 15, 15]]),
        room("chancel", "Chancel", "carpet_red", "chapel", [[16, 4, 15, 8]]),
        room("vestry", "Vestry", "wood_dark", "study", [[5, 4, 10, 6]], lit=False),
        room("crypt", "Crypt", "stone", "cellar", [[5, 11, 10, 7]], lit=False),
        room("refectory", "Refectory", "parquet", "dining", [[5, 19, 10, 9]]),
        room("rector_study", "Rector's Study", "carpet_green", "study", [[32, 4, 11, 6]]),
        room("kitchen", "Rectory Kitchen", "tile_checker", "kitchen", [[32, 11, 11, 7]]),
        room("bedroom", "Rector's Bedroom", "carpet_blue", "bedroom", [[32, 19, 6, 9]], lit=False),
        room("bathroom", "Bathroom", "tile_white", "bathroom", [[39, 19, 4, 9]], lit=False),
    ],
    "doors": [
        [22, 28], [23, 28], [10, 28], [35, 28], [4, 7], [4, 22], [43, 7], [43, 14], [10, 3], [18, 3], [37, 3],
        [23, 12], [15, 7], [31, 7], [10, 10], [15, 15], [10, 18], [15, 24], [31, 15], [31, 24], [37, 10],
        [35, 18], [38, 22], [41, 18],
    ],
    "furniture": [
        # nave
        ["pew", 17, 15, 0], ["pew", 26, 15, 0], ["pew", 17, 18, 0], ["pew", 26, 18, 0], ["pew", 17, 21, 0],
        ["pew", 26, 21, 0], ["pew", 17, 24, 0], ["pew", 26, 24, 0], ["candelabra", 16, 13, 0], ["candelabra", 30, 13, 0],
        ["candelabra", 16, 27, 0], ["candelabra", 30, 27, 0],
        # chancel
        ["altar", 22, 4, 0], ["candelabra", 20, 4, 0], ["candelabra", 26, 4, 0], ["rug_rect", 21, 7, 0],
        ["pew", 16, 10, 0], ["pew", 27, 10, 0], ["wall_mirror", 30, 5, 1],
        # vestry
        ["wardrobe", 5, 4, 0], ["trunk", 12, 4, 0], ["desk", 11, 6, 0], ["chair", 12, 8, 2], ["woodpile", 5, 9, 0],
        # crypt
        ["coffin", 6, 12, 0], ["coffin", 9, 12, 0], ["coffin", 12, 12, 0], ["candelabra", 14, 17, 0], ["crates", 5, 16, 0],
        # refectory
        ["dining_table", 7, 21, 0], ["cabinet", 5, 27, 0], ["cabinet", 12, 27, 0], ["candelabra", 5, 19, 0],
        ["grandfather_clock", 14, 19, 0], ["fireplace", 11, 19, 0],
        # rector's study
        ["bookshelf", 32, 4, 0], ["bookshelf", 39, 4, 0], ["desk", 34, 6, 0], ["chair", 35, 8, 2],
        ["armchair", 40, 7, 0], ["floor_lamp", 42, 9, 0],
        # kitchen
        ["stove", 32, 11, 0], ["counter", 34, 11, 0], ["sink_kitchen", 39, 11, 0], ["icebox", 42, 11, 0],
        ["counter", 35, 14, 0], ["counter", 37, 14, 0], ["barrel", 42, 17, 0], ["chair", 33, 16, 0],
        # bedroom
        ["bed_single", 36, 23, 2], ["nightstand", 34, 27, 0], ["wardrobe", 32, 19, 0], ["rug_rect", 32, 20, 0],
        ["trunk", 36, 27, 0],
        # bathroom
        ["bathtub", 41, 25, 0], ["toilet", 39, 27, 0], ["washbasin", 42, 19, 0], ["wall_mirror", 42, 20, 1],
        # graveyard
        ["gravestone", 5, 30, 0], ["gravestone", 8, 31, 0], ["gravestone", 13, 30, 0], ["gravestone", 30, 30, 0],
        ["gravestone", 39, 31, 0], ["gravestone", 42, 30, 0], ["tree", 1, 10, 0], ["tree", 44, 24, 0],
        ["gravestone", 2, 17, 0], ["gravestone", 45, 19, 0], ["tree", 17, 30, 0], ["tree", 26, 30, 0],
        ["hedge", 28, 1, 0], ["hedge", 14, 1, 0],
    ],
})

# ---------------------------------------------------------------------------
# 5. Marrow Street Townhouse — narrow terraced house, courtyard and back alley.
HOUSES.append({
    "id": "marrow_street", "name": "Marrow Street Townhouse",
    "blurb": "Three generations lived here. One of them never left.",
    "size": [40, 34], "spawn": [19, 31], "npcs": 3,
    "rooms": [
        room("street", "Marrow Street", "stone", "yard", [[1, 29, 38, 4]], lit=False, outdoor=True),
        room("alley", "Back Alley", "gravel", "yard", [[1, 1, 38, 2], [1, 3, 2, 26], [37, 3, 2, 26]], lit=False, outdoor=True),
        room("entry", "Entry Hall", "wood_dark", "hall", [[16, 20, 8, 8]]),
        room("front_parlor", "Front Parlor", "carpet_red", "living", [[4, 20, 11, 8]]),
        room("drawing_room", "Drawing Room", "carpet_blue", "living", [[25, 20, 11, 8]], lit=False),
        room("stair_hall", "Stair Hall", "parquet", "hall", [[4, 15, 32, 4]]),
        room("dining", "Dining Room", "parquet", "dining", [[4, 9, 10, 5]]),
        room("kitchen", "Kitchen", "tile_checker", "kitchen", [[15, 9, 10, 5]]),
        room("scullery", "Scullery", "stone", "pantry", [[26, 9, 4, 5]], lit=False),
        room("bedroom", "Bedroom", "carpet_green", "bedroom", [[31, 9, 5, 5]], lit=False),
        room("courtyard", "Courtyard", "stone", "yard", [[4, 4, 14, 4]], lit=False, outdoor=True),
        room("coal_shed", "Coal Shed", "dirt", "shed", [[19, 4, 5, 4]], lit=False),
        room("bathroom", "Bathroom", "tile_white", "bathroom", [[25, 4, 5, 4]]),
        room("box_room", "Box Room", "wood_light", "bedroom", [[31, 4, 5, 4]], lit=False),
    ],
    "doors": [
        [19, 28], [20, 28], [9, 28], [30, 28], [3, 17], [36, 17], [3, 23], [36, 23], [3, 11],
        [8, 3], [21, 3], [33, 3], [15, 24], [24, 24], [19, 19], [20, 19], [9, 19], [30, 19],
        [9, 14], [20, 14], [28, 14], [33, 14], [14, 11], [25, 11], [30, 11], [10, 8], [18, 6],
        [22, 8], [28, 8], [33, 8], [30, 6], [24, 6],
    ],
    "furniture": [
        # entry hall
        ["rug_rect", 17, 22, 0], ["grandfather_clock", 16, 20, 0], ["side_table", 23, 20, 0], ["potted_plant", 16, 27, 0],
        ["potted_plant", 23, 27, 0], ["wall_mirror", 23, 25, 1],
        # front parlor
        ["fireplace", 6, 20, 0], ["rug_round", 7, 22, 0], ["sofa", 4, 26, 2], ["armchair", 12, 21, 0],
        ["piano", 11, 25, 0], ["candelabra", 4, 20, 0],
        # drawing room
        ["bookshelf", 25, 20, 0], ["bookshelf", 32, 20, 0], ["desk", 30, 24, 0], ["chair", 31, 26, 2],
        ["armchair", 26, 25, 0], ["floor_lamp", 35, 27, 0], ["rug_rect", 27, 22, 0],
        # stair hall
        ["rug_rect", 12, 15, 0], ["rug_rect", 24, 15, 0], ["side_table", 4, 15, 0], ["potted_plant", 35, 15, 0],
        ["candelabra", 18, 15, 0],
        # dining
        ["dining_table", 6, 10, 0], ["cabinet", 4, 13, 0], ["candelabra", 13, 9, 0],
        # kitchen
        ["stove", 15, 9, 0], ["counter", 17, 9, 0], ["sink_kitchen", 20, 9, 0], ["icebox", 24, 13, 0],
        ["counter", 18, 12, 0], ["barrel", 15, 13, 0],
        # scullery
        ["wash_tub", 26, 9, 0], ["barrel", 29, 13, 0], ["cabinet", 26, 13, 0],
        # bedroom
        ["bed_single", 34, 10, 0], ["nightstand", 31, 13, 0], ["dresser", 31, 9, 0],
        # courtyard
        ["tree", 4, 4, 0], ["wash_tub", 15, 4, 0], ["barrel", 12, 7, 0],
        # coal shed
        ["crates", 19, 4, 0], ["woodpile", 22, 4, 0], ["workbench", 19, 7, 2],
        # bathroom
        ["bathtub", 25, 4, 1], ["toilet", 29, 7, 0], ["washbasin", 29, 4, 0], ["wall_mirror", 26, 7, 2],
        # box room
        ["trunk", 31, 4, 0], ["bed_single", 34, 4, 0], ["barrel", 31, 7, 0],
        # street/alley
        ["tree", 2, 30, 0], ["tree", 35, 30, 0], ["barrel", 12, 1, 0], ["crates", 26, 1, 0], ["hedge", 13, 31, 0],
        ["hedge", 25, 31, 0],
    ],
})


FURN_SIZES = {}


def load_furniture_sizes():
    import re
    path = os.path.join(ROOT, "scripts", "data", "defs.gd")
    text = open(path).read()
    for m in re.finditer(r'"(\w+)": \{"size": Vector2i\((\d+), (\d+)\), "solid": (true|false)', text):
        FURN_SIZES[m.group(1)] = (int(m.group(2)), int(m.group(3)), m.group(4) == "true")


def rasterize(h):
    w, ht = h["size"]
    grid = [[None] * w for _ in range(ht)]
    for r in h["rooms"]:
        for x, y, rw, rh in r["rects"]:
            for yy in range(y, y + rh):
                for xx in range(x, x + rw):
                    assert grid[yy][xx] is None, f"{h['id']}: overlap at {xx},{yy} ({r['id']})"
                    grid[yy][xx] = r["id"]
    walls = set()
    for y in range(ht):
        for x in range(w):
            if grid[y][x] is None:
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < ht and grid[ny][nx] not in (None, "#"):
                            walls.add((x, y))
    for (x, y) in walls:
        grid[y][x] = "#"
    for x, y in h["doors"]:
        assert grid[y][x] == "#", f"{h['id']}: door {x},{y} is not on a wall ({grid[y][x]})"
        grid[y][x] = "+"
    return grid


def preview(h, grid, out_dir):
    from PIL import Image, ImageDraw
    s = 14
    w, ht = h["size"]
    img = Image.new("RGB", (w * s, ht * s), (10, 10, 12))
    d = ImageDraw.Draw(img)
    palette = {}
    import hashlib
    for r in h["rooms"]:
        hh = hashlib.md5(r["id"].encode()).digest()
        palette[r["id"]] = (60 + hh[0] % 120, 60 + hh[1] % 120, 60 + hh[2] % 120)
    for y in range(ht):
        for x in range(w):
            c = grid[y][x]
            if c is None:
                continue
            col = (30, 30, 30) if c == "#" else (200, 170, 60) if c == "+" else palette[c]
            d.rectangle([x * s, y * s, x * s + s - 1, y * s + s - 1], fill=col)
    for f in h["furniture"]:
        t, x, y, rot = f
        fw, fh, solid = FURN_SIZES[t]
        if rot % 2 == 1:
            fw, fh = fh, fw
        d.rectangle([x * s + 1, y * s + 1, (x + fw) * s - 2, (y + fh) * s - 2],
                    outline=(255, 255, 255) if solid else (120, 120, 255), width=1)
    for r in h["rooms"]:
        x, y, rw, rh = r["rects"][0]
        d.text((x * s + 2, y * s + 2), r["name"], fill=(255, 255, 255))
    sx, sy = h["spawn"]
    d.ellipse([sx * s, sy * s, sx * s + s, sy * s + s], fill=(255, 0, 0))
    img.save(os.path.join(out_dir, h["id"] + ".png"))


def main():
    load_furniture_sizes()
    out_dir = None
    if "--preview" in sys.argv:
        out_dir = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(out_dir, exist_ok=True)
    dest = os.path.join(ROOT, "data", "houses")
    os.makedirs(dest, exist_ok=True)
    index = []
    for h in HOUSES:
        grid = rasterize(h)
        for f in h["furniture"]:
            assert f[0] in FURN_SIZES, f"{h['id']}: unknown furniture {f[0]}"
        with open(os.path.join(dest, h["id"] + ".json"), "w") as fp:
            json.dump(h, fp, indent=1)
        index.append(h["id"])
        if out_dir:
            preview(h, grid, out_dir)
    with open(os.path.join(dest, "index.json"), "w") as fp:
        json.dump(index, fp)
    print("wrote", index)




def validate(h, grid):
    """Returns a list of problems: furniture placement, blocked doors, connectivity, room access."""
    problems = []
    w, ht = h["size"]
    solid = set()
    for f in h["furniture"]:
        t, x, y, rot = f
        fw, fh, is_solid = FURN_SIZES[t]
        if rot % 2 == 1:
            fw, fh = fh, fw
        for yy in range(y, y + fh):
            for xx in range(x, x + fw):
                if not (0 <= xx < w and 0 <= yy < ht) or grid[yy][xx] in (None, "#", "+"):
                    problems.append(f"{t}@{x},{y} covers non-floor {xx},{yy}")
                elif is_solid:
                    if (xx, yy) in solid:
                        problems.append(f"{t}@{x},{y} overlaps solid furniture at {xx},{yy}")
                    solid.add((xx, yy))
    for x, y in h["doors"]:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < ht and grid[ny][nx] not in (None, "#", "+") and (nx, ny) in solid:
                problems.append(f"door {x},{y} blocked by furniture at {nx},{ny}")
    walk = {(x, y) for y in range(ht) for x in range(w) if grid[y][x] not in (None, "#") and (x, y) not in solid}
    start = tuple(h["spawn"])
    if start not in walk:
        problems.append("spawn not walkable")
        return problems
    seen = {start}
    stack = [start]
    while stack:
        x, y = stack.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n in walk and n not in seen:
                seen.add(n)
                stack.append(n)
    lost = walk - seen
    if lost:
        problems.append(f"{len(lost)} unreachable walkable cells e.g. {sorted(lost)[:6]}")
    # Dead ends: rooms with a single doorway (outdoor-open boundaries count as exits).
    for r in h["rooms"]:
        exits = 0
        cells = {(x, y) for y in range(ht) for x in range(w) if grid[y][x] == r["id"]}
        for x, y in h["doors"]:
            if any((x + dx, y + dy) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                exits += 1
        open_edges = any(grid[y + dy][x + dx] not in (None, "#", "+", r["id"])
                         for (x, y) in cells for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                         if 0 <= x + dx < w and 0 <= y + dy < ht)
        if exits + (1 if open_edges else 0) < 2:
            problems.append(f"dead end room: {r['id']} ({exits} doors)")
    return problems


if __name__ == "__main__" and "--validate" in sys.argv:
    load_furniture_sizes()
    bad = False
    for h in HOUSES:
        try:
            g = rasterize(h)
        except AssertionError as e:
            print("ERROR", e); bad = True; continue
        p = validate(h, g)
        print(h["id"], "OK" if not p else "")
        for x in p:
            print("   ", x)
        bad = bad or bool(p)
    sys.exit(1 if bad else 0)


if __name__ == "__main__" and "--validate" not in sys.argv:
    main()
