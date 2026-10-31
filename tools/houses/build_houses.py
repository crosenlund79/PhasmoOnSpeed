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

# ---------------------------------------------------------------------------
# 6. The Black Lantern Inn — coaching inn: common room, taproom, kitchen, stables.
HOUSES.append({
    "id": "tavern", "name": "The Black Lantern Inn",
    "blurb": "Last orders were called in 1871. Somebody is still drinking.",
    "size": [50, 34], "spawn": [24, 30], "npcs": 3,
    "rooms": [
        room("west_lane", "Drovers' Lane", "gravel", "yard", [[1, 1, 3, 27]], lit=False, outdoor=True),
        room("stable_yard", "Stable Yard", "dirt", "yard", [[43, 1, 6, 27]], lit=False, outdoor=True),
        room("coaching_yard", "Coaching Yard", "gravel", "yard", [[1, 28, 48, 5]], lit=False, outdoor=True),
        room("kitchen", "Inn Kitchen", "tile_checker", "kitchen", [[5, 1, 11, 7]]),
        room("pantry", "Pantry", "stone", "pantry", [[17, 1, 6, 7]], lit=False),
        room("brewhouse", "Brewhouse", "stone", "shed", [[24, 1, 6, 7]], lit=False),
        room("stables", "Stables", "dirt", "shed", [[31, 1, 11, 7]], lit=False),
        room("back_passage", "Back Passage", "wood_dark", "hall", [[5, 9, 37, 3]], lit=False),
        room("common_room", "Common Room", "wood_dark", "dining", [[5, 13, 18, 14]]),
        room("taproom", "Taproom", "parquet", "living", [[24, 13, 10, 14]]),
        room("snug", "The Snug", "carpet_red", "living", [[35, 13, 7, 6]], lit=False),
        room("office", "Innkeeper's Office", "carpet_green", "study", [[35, 20, 7, 7]]),
    ],
    "doors": [
        [10, 8], [19, 8], [27, 8], [36, 8], [16, 4], [23, 4], [30, 4], [4, 4], [42, 4], [4, 10], [42, 10],
        [10, 12], [28, 12], [38, 12], [23, 17], [23, 22], [34, 15], [34, 23], [38, 19],
        [13, 27], [14, 27], [29, 27], [38, 27],
    ],
    "furniture": [
        # kitchen (south-west corner: cellar stairs)
        ["stove", 5, 1, 0], ["stove", 7, 1, 0], ["counter", 9, 1, 0], ["sink_kitchen", 12, 1, 0], ["icebox", 14, 1, 0],
        ["dining_table", 7, 4, 0], ["barrel", 15, 7, 0], ["cabinet", 12, 7, 0],
        # pantry
        ["storage_shelf", 17, 1, 0], ["cabinet", 20, 1, 0], ["barrel", 22, 1, 0], ["crates", 21, 5, 0], ["barrel", 17, 7, 0],
        # brewhouse
        ["keg_rack", 24, 1, 0], ["wash_tub", 27, 1, 0], ["workbench", 24, 7, 0], ["woodpile", 28, 7, 0],
        # stables
        ["hay", 31, 1, 0], ["workbench", 35, 1, 0], ["hay", 39, 1, 0], ["barrel", 41, 1, 0], ["hay", 31, 6, 0],
        ["crates", 33, 5, 0], ["wash_tub", 39, 6, 0],
        # back passage
        ["grandfather_clock", 5, 9, 0], ["rug_rect", 13, 9, 0], ["wall_mirror", 24, 9, 0], ["side_table", 33, 11, 0],
        ["potted_plant", 41, 11, 0],
        # common room (south-west corner: the main staircase)
        ["fireplace", 5, 13, 0], ["pew", 15, 13, 0], ["dining_table", 8, 16, 0], ["dining_table", 15, 16, 0],
        ["dining_table", 8, 21, 0], ["dining_table", 15, 21, 0], ["candelabra", 22, 13, 0], ["candelabra", 22, 26, 0],
        ["barrel", 19, 26, 0],
        # taproom
        ["bar_counter", 30, 14, 1], ["bar_counter", 30, 20, 1], ["keg_rack", 33, 18, 1], ["chair", 29, 15, 0],
        ["chair", 29, 21, 0], ["dining_table", 25, 19, 1], ["candelabra", 24, 13, 0], ["barrel", 31, 26, 0],
        ["wine_rack", 31, 13, 0],
        # snug
        ["armchair", 35, 13, 0], ["fireplace", 39, 13, 0], ["armchair", 40, 16, 0], ["coffee_table", 36, 17, 0],
        # office (south-east corner: back stairs)
        ["bookshelf", 35, 20, 0], ["cabinet", 40, 20, 0], ["desk", 38, 22, 0], ["chair", 39, 24, 2], ["trunk", 35, 26, 0],
        # outside
        ["hay", 45, 2, 0], ["wash_tub", 45, 8, 0], ["barrel", 47, 20, 0], ["tree", 45, 23, 0], ["barrel", 1, 7, 0],
        ["crates", 1, 18, 0], ["tree", 2, 29, 0], ["barrel", 20, 29, 0], ["hedge", 40, 30, 0], ["hedge", 33, 31, 0],
        ["floor_lamp", 12, 28, 0], ["floor_lamp", 30, 28, 0],
    ],
})

# ---------------------------------------------------------------------------
# 7. Saltmarsh Harbour — warehouse, harbour master's office, quays, jetties and a
# moored lugger over black water (water = solid tiles drawn under the actors).
HARBOUR_WATER = [1, 24, 54, 14]           # x, y, w, h of the basin (2-cell tiles, odd x / even y)
HARBOUR_DRY = [[9, 24, 2, 12], [29, 24, 2, 12], [31, 34, 6, 2], [37, 24, 2, 12]]   # jetties (part of the quay)
HARBOUR_DECK = [[13, 26, 4, 10], [11, 30, 2, 2]]                                   # the lugger's deck + gangway


def harbour_water():
    """Rects of open water (basin minus jetties and deck) and the water tiles covering them."""
    x0, y0, w, h = HARBOUR_WATER
    dry = set()
    for rx, ry, rw, rh in HARBOUR_DRY + HARBOUR_DECK:
        dry |= {(x, y) for x in range(rx, rx + rw) for y in range(ry, ry + rh)}
    rects, tiles = [], []
    for y in range(y0, y0 + h, 2):
        x = x0
        while x < x0 + w:
            if (x, y) in dry:
                x += 2
                continue
            start = x
            while x < x0 + w and (x, y) not in dry:
                tiles.append(["water", x, y, 0])
                x += 2
            rects.append([start, y, x - start, 2])
    return rects, tiles


_HW_RECTS, _HW_TILES = harbour_water()

HOUSES.append({
    "id": "harbor", "name": "Saltmarsh Harbour",
    "blurb": "The tide brought the boat back. It did not bring back the crew.",
    "size": [56, 39], "spawn": [27, 2], "npcs": 2,
    "rooms": [
        room("harbour_road", "Harbour Road", "gravel", "yard", [[1, 1, 54, 3]], lit=False, outdoor=True),
        room("rope_walk", "Rope Walk", "gravel", "yard", [[1, 4, 3, 16]], lit=False, outdoor=True),
        room("quay", "Quay and Jetties", "wood_dark", "yard", [[1, 20, 54, 4]] + HARBOUR_DRY + _HW_RECTS, lit=False, outdoor=True),
        room("deck", "Deck of the Mary Ellen", "wood_light", "yard", HARBOUR_DECK, lit=False, outdoor=True),
        room("warehouse", "Warehouse", "wood_dark", "shed", [[5, 5, 18, 8]], lit=False),
        room("salting_house", "Salting House", "stone", "pantry", [[5, 14, 11, 5]], lit=False),
        room("cooperage", "Cooperage", "dirt", "shed", [[17, 14, 6, 5]], lit=False),
        room("harbour_office", "Harbour Master's Office", "carpet_green", "study", [[24, 5, 10, 7]]),
        room("customs_hall", "Customs Hall", "stone", "hall", [[24, 13, 10, 6]]),
        room("mess", "Seamen's Mess", "tile_checker", "kitchen", [[35, 5, 11, 7]]),
        room("chandlery", "Ship Chandlery", "wood_light", "pantry", [[35, 13, 11, 6]], lit=False),
        room("net_shed", "Net Shed", "dirt", "shed", [[47, 5, 8, 14]], lit=False),
    ],
    "doors": [
        [4, 8], [12, 4], [23, 8], [10, 13], [4, 16], [16, 16], [10, 19], [20, 19], [20, 13],
        [28, 4], [28, 12], [34, 8], [28, 19], [34, 16], [23, 16], [40, 4], [40, 12], [40, 19], [46, 16],
        [50, 4], [50, 19], [46, 8],
    ],
    "furniture": _HW_TILES + [
        ["boat_hull", 12, 24, 0],
        # the lugger's deck
        ["barrel", 13, 26, 0], ["crates", 15, 27, 0], ["rope_coil", 16, 31, 0], ["fishing_net", 13, 33, 0], ["barrel", 16, 35, 0],
        # harbour road and rope walk
        ["floor_lamp", 8, 1, 0], ["floor_lamp", 34, 1, 0], ["floor_lamp", 46, 1, 0], ["crates", 19, 1, 0], ["barrel", 22, 1, 0],
        ["rope_coil", 31, 2, 0], ["barrel", 1, 6, 0], ["crates", 1, 10, 0],
        # quay
        ["bollard", 7, 23, 0], ["bollard", 12, 23, 0], ["bollard", 17, 23, 0], ["bollard", 26, 23, 0], ["bollard", 35, 23, 0],
        ["bollard", 42, 23, 0], ["bollard", 52, 23, 0], ["rope_coil", 8, 21, 0], ["crates", 44, 21, 0], ["barrel", 47, 20, 0],
        ["fishing_net", 22, 21, 0], ["floor_lamp", 31, 20, 0], ["rope_coil", 10, 35, 0], ["bollard", 38, 35, 0],
        # warehouse (north-east corner: loft stairs, south-west corner: cellar stairs)
        ["crates", 6, 5, 0], ["crates", 14, 5, 0], ["storage_shelf", 16, 5, 0], ["barrel", 19, 5, 0], ["crates", 8, 9, 0],
        ["crates", 14, 9, 0], ["fishing_net", 17, 9, 0], ["barrel", 19, 11, 0], ["barrel", 20, 11, 0], ["rope_coil", 11, 7, 0],
        # salting house
        ["barrel", 5, 14, 0], ["barrel", 6, 14, 0], ["counter", 12, 14, 0], ["wash_tub", 13, 17, 0], ["cabinet", 5, 18, 0],
        # cooperage
        ["workbench", 17, 14, 0], ["barrel", 22, 14, 0], ["barrel", 22, 15, 0], ["woodpile", 21, 18, 0], ["barrel", 17, 18, 0],
        # harbour master's office (north-east corner: stairs up)
        ["bookshelf", 24, 5, 0], ["grandfather_clock", 27, 5, 0], ["desk", 29, 8, 0], ["chair", 30, 10, 2],
        ["cabinet", 24, 11, 0], ["wall_mirror", 31, 11, 0], ["side_table", 33, 11, 0],
        # customs hall
        ["pew", 24, 14, 0], ["counter", 30, 13, 0], ["cabinet", 32, 13, 0], ["crates", 31, 17, 0], ["rug_rect", 25, 15, 0],
        ["wall_mirror", 24, 18, 0],
        # seamen's mess
        ["stove", 36, 5, 0], ["counter", 38, 5, 0], ["sink_kitchen", 42, 5, 0], ["icebox", 44, 5, 0],
        ["dining_table", 38, 7, 0], ["chair", 37, 8, 0], ["chair", 43, 8, 0], ["barrel", 35, 11, 0],
        # chandlery (north-east corner: cellar stairs)
        ["storage_shelf", 35, 13, 0], ["storage_shelf", 41, 13, 0], ["crates", 37, 17, 0], ["rope_coil", 42, 18, 0],
        ["cabinet", 43, 16, 0], ["barrel", 35, 18, 0],
        # net shed
        ["fishing_net", 48, 6, 0], ["fishing_net", 52, 10, 0], ["fishing_net", 48, 12, 0], ["rope_coil", 53, 5, 0],
        ["rope_coil", 54, 5, 0], ["barrel", 54, 18, 0], ["crates", 52, 16, 0], ["workbench", 54, 8, 1],
    ],
})


# ---------------------------------------------------------------------------
# Basements (revision 2). Coordinates are local to the basement; the basement
# is placed below the main floor with a void gap so the two levels never share
# walls, light or line of sight. Rooms get "level": -1. Staircases link a cell
# on each level to a landing cell beside its partner (no ping-pong).
FLOOR_GAP = 12


def broom(rid, name, floor, kind, rects, lit=False):
    r = room(rid, name, floor, kind, rects, lit=lit)
    r["level"] = -1
    return r


BASEMENTS = {
    "ashgrove": {
        "size": [30, 14],
        "rooms": [
            broom("root_cellar", "Root Cellar", "stone", "cellar", [[4, 1, 10, 6]]),
            broom("cellar_store", "Cellar Storage", "dirt", "cellar", [[15, 1, 10, 6]]),
            broom("cold_store", "Cold Store", "stone", "cellar", [[4, 8, 6, 4]]),
            broom("coal_hole", "Coal Hole", "dirt", "shed", [[11, 8, 14, 4]], lit=True),
        ],
        "doors": [[14, 3], [6, 7], [20, 7], [10, 10], [12, 7]],
        "furniture": [
            ["storage_shelf", 5, 1, 0], ["wine_rack", 9, 1, 0], ["barrel", 13, 1, 0], ["crates", 10, 5, 0], ["pipes", 4, 6, 0],
            ["old_trunk", 16, 1, 0], ["covered_armchair", 19, 1, 0], ["storage_shelf", 22, 1, 0], ["broken_chair", 16, 5, 0],
            ["debris", 17, 3, 0], ["water_tank", 4, 8, 0], ["barrel", 8, 11, 0], ["coal_pile", 14, 9, 0], ["boiler", 21, 8, 0],
            ["boards", 17, 10, 0],
        ],
        "stairs": [
            {"name": "Cellar Stairs", "a": [6, 11], "a_land": [7, 11], "b": [5, 3], "b_land": [6, 3], "style": "stairs"},
            {"name": "Garden Hatch", "a": [33, 4], "a_land": [32, 4], "b": [23, 4], "b_land": [22, 4], "style": "hatch"},
        ],
    },
    "blackwood": {
        "size": [44, 19],
        "rooms": [
            broom("wine_cellar", "Wine Cellar", "stone", "cellar", [[4, 1, 14, 7]]),
            broom("servants_quarters", "Servants' Quarters", "wood_light", "bedroom", [[19, 1, 10, 7]]),
            broom("boiler_room", "Boiler Room", "stone", "cellar", [[30, 1, 10, 7]], lit=True),
            broom("undercroft", "Undercroft Passage", "stone", "hall", [[4, 9, 36, 3]]),
            broom("old_laundry", "Old Laundry", "tile_white", "laundry", [[4, 13, 12, 5]]),
            broom("strongroom", "Strongroom", "wood_dark", "study", [[17, 13, 9, 5]]),
            broom("coal_store", "Coal Store", "dirt", "shed", [[27, 13, 13, 5]]),
        ],
        "doors": [[18, 4], [29, 4], [10, 8], [24, 8], [35, 8], [9, 12], [21, 12], [33, 12], [16, 15], [26, 15]],
        "furniture": [
            ["wine_rack", 5, 1, 0], ["wine_rack", 9, 1, 0], ["wine_rack", 13, 1, 0], ["wine_rack", 5, 4, 0], ["wine_rack", 12, 4, 0],
            ["barrel", 16, 6, 0], ["bed_single", 20, 1, 1], ["old_trunk", 25, 1, 0], ["covered_armchair", 26, 4, 0],
            ["broken_chair", 21, 6, 0], ["debris", 22, 4, 0], ["boiler", 34, 1, 0], ["pipes", 30, 1, 0], ["water_tank", 38, 5, 0],
            ["coal_pile", 31, 5, 0], ["pipes", 12, 9, 0], ["debris", 28, 10, 0], ["wash_tub", 4, 13, 0], ["wash_tub", 7, 13, 0],
            ["storage_shelf", 11, 17, 0], ["boards", 5, 16, 0], ["old_trunk", 18, 13, 0], ["cabinet", 22, 17, 0],
            ["storage_shelf", 23, 13, 0], ["coal_pile", 28, 13, 0], ["coal_pile", 37, 16, 0], ["crates", 31, 16, 0], ["barrel", 39, 13, 0],
        ],
        "stairs": [
            {"name": "Cellar Stairs", "a": [12, 9], "a_land": [11, 9], "b": [17, 2], "b_land": [16, 2], "style": "stairs"},
            {"name": "Servants' Stairs", "a": [44, 2], "a_land": [45, 2], "b": [38, 2], "b_land": [37, 2], "style": "stairs"},
        ],
    },
    "hollow_lane": {
        "size": [38, 18],
        "rooms": [
            broom("root_store", "Root Store", "dirt", "cellar", [[4, 1, 9, 6]]),
            broom("cellar_passage", "Cellar Passage", "stone", "hall", [[14, 1, 3, 10], [4, 8, 10, 3]]),
            broom("old_workshop", "Old Workshop", "wood_dark", "shed", [[18, 1, 12, 6]], lit=True),
            broom("pump_room", "Pump Room", "stone", "cellar", [[31, 1, 5, 9]]),
            broom("feed_store", "Feed Store", "dirt", "shed", [[4, 12, 13, 5]]),
            broom("well_room", "Well Room", "stone", "cellar", [[18, 8, 12, 9]]),
        ],
        "doors": [[8, 7], [13, 3], [17, 3], [30, 3], [17, 9], [24, 7], [30, 8], [8, 11], [17, 14]],
        "furniture": [
            ["storage_shelf", 8, 1, 0], ["barrel", 12, 1, 0], ["crates", 4, 5, 0], ["pipes", 4, 10, 0], ["debris", 10, 9, 0],
            ["workbench", 19, 1, 0], ["woodpile", 23, 1, 0], ["storage_shelf", 26, 1, 0], ["crates", 27, 5, 0],
            ["broken_chair", 20, 5, 0], ["boards", 22, 4, 0], ["boiler", 32, 1, 0], ["water_tank", 33, 6, 0],
            ["hay", 5, 13, 0], ["hay", 13, 13, 0], ["barrel", 4, 16, 0], ["water_tank", 23, 11, 0], ["coal_pile", 27, 14, 0],
            ["barrel", 19, 16, 0], ["crates", 19, 10, 0],
        ],
        "stairs": [
            {"name": "Cellar Stairs", "a": [24, 22], "a_land": [23, 22], "b": [5, 2], "b_land": [6, 2], "style": "stairs"},
            {"name": "Barn Trapdoor", "a": [39, 13], "a_land": [39, 12], "b": [34, 4], "b_land": [33, 4], "style": "hatch"},
        ],
    },
    "evangeline": {
        "size": [46, 17],
        "rooms": [
            broom("undercroft", "Undercroft", "stone", "cellar", [[4, 1, 38, 2]]),
            broom("parish_archive", "Parish Archive", "wood_dark", "study", [[4, 4, 10, 6]], lit=True),
            broom("ossuary", "Ossuary", "stone", "cellar", [[15, 4, 16, 7]]),
            broom("boiler_house", "Boiler House", "stone", "cellar", [[32, 4, 10, 6]]),
            broom("cistern", "Cistern", "stone", "cellar", [[4, 11, 10, 5]]),
            broom("service_tunnel", "Service Tunnel", "stone", "hall", [[15, 12, 16, 4]]),
            broom("church_stores", "Church Stores", "dirt", "shed", [[32, 11, 10, 5]]),
        ],
        "doors": [[8, 3], [22, 3], [37, 3], [14, 7], [31, 7], [8, 10], [37, 10], [14, 13], [31, 13], [22, 11]],
        "furniture": [
            ["candelabra", 5, 1, 0], ["debris", 26, 1, 0], ["pipes", 30, 2, 0],
            ["bookshelf", 4, 4, 0], ["bookshelf", 10, 4, 0], ["desk", 5, 7, 0], ["old_trunk", 11, 8, 0],
            ["coffin", 17, 5, 0], ["coffin", 27, 5, 0], ["candelabra", 20, 9, 0], ["debris", 24, 7, 0],
            ["boiler", 38, 4, 0], ["coal_pile", 33, 8, 0], ["pipes", 36, 9, 0],
            ["water_tank", 5, 12, 0], ["water_tank", 10, 13, 0], ["crates", 33, 11, 0], ["storage_shelf", 38, 15, 0],
            ["barrel", 41, 11, 0], ["pipes", 17, 12, 0], ["debris", 25, 13, 0],
        ],
        "stairs": [
            {"name": "Crypt Stairs", "a": [7, 17], "a_land": [8, 17], "b": [6, 2], "b_land": [7, 2], "style": "stairs"},
            {"name": "Kitchen Stairs", "a": [41, 15], "a_land": [40, 15], "b": [40, 7], "b_land": [39, 7], "style": "stairs"},
        ],
    },
    "marrow_street": {
        "size": [36, 17],
        "rooms": [
            broom("coal_cellar", "Coal Vault", "dirt", "shed", [[4, 1, 7, 15]]),
            broom("basement_passage", "Basement Passage", "stone", "hall", [[12, 1, 20, 2]]),
            broom("utility_room", "Utility Room", "stone", "cellar", [[12, 4, 9, 5]], lit=True),
            broom("wine_store", "Wine Store", "stone", "cellar", [[22, 4, 10, 5]]),
            broom("laundry", "Laundry", "tile_white", "laundry", [[12, 10, 9, 6]]),
            broom("lumber_room", "Lumber Room", "wood_light", "shed", [[22, 10, 10, 6]]),
        ],
        "doors": [[11, 2], [11, 6], [11, 12], [16, 3], [27, 3], [21, 6], [16, 9], [27, 9], [21, 13]],
        "furniture": [
            ["coal_pile", 4, 4, 0], ["coal_pile", 8, 9, 0], ["barrel", 4, 14, 0], ["boards", 5, 12, 0],
            ["boiler", 13, 4, 0], ["water_tank", 18, 7, 0], ["pipes", 13, 1, 0],
            ["wine_rack", 22, 4, 0], ["wine_rack", 28, 4, 0], ["wine_rack", 23, 8, 0],
            ["wash_tub", 12, 14, 0], ["wash_tub", 17, 10, 0], ["pipes", 13, 10, 0],
            ["covered_sofa", 23, 14, 0], ["covered_armchair", 29, 10, 0], ["old_trunk", 25, 11, 0], ["broken_chair", 31, 15, 0],
        ],
        "stairs": [
            {"name": "Coal Chute", "a": [9, 5], "a_land": [10, 5], "b": [6, 2], "b_land": [7, 2], "style": "hatch"},
            {"name": "Basement Stairs", "a": [34, 17], "a_land": [33, 17], "b": [30, 7], "b_land": [29, 7], "style": "stairs"},
        ],
    },
    "tavern": {
        "size": [44, 17],
        "rooms": [
            broom("beer_cellar", "Beer Cellar", "stone", "cellar", [[5, 1, 14, 7]]),
            broom("boiler_room", "Boiler Room", "stone", "cellar", [[20, 1, 9, 7]], lit=True),
            broom("wine_vault", "Wine Vault", "stone", "cellar", [[30, 1, 12, 7]]),
            broom("cellar_passage", "Cellar Passage", "stone", "hall", [[5, 9, 37, 2]]),
            broom("smugglers_hold", "Smugglers' Hold", "dirt", "cellar", [[5, 12, 18, 4]]),
            broom("coal_store", "Coal Store", "dirt", "shed", [[24, 12, 18, 4]]),
        ],
        "doors": [[10, 8], [24, 8], [36, 8], [19, 4], [29, 4], [12, 11], [32, 11], [23, 13]],
        "furniture": [
            ["keg_rack", 9, 1, 0], ["keg_rack", 13, 1, 0], ["keg_rack", 5, 4, 1], ["barrel", 17, 1, 0], ["barrel", 18, 1, 0],
            ["barrel", 8, 6, 0], ["barrel", 12, 6, 0], ["crates", 16, 6, 0],
            ["boiler", 23, 1, 0], ["coal_pile", 20, 5, 0], ["pipes", 25, 7, 0], ["water_tank", 27, 1, 0],
            ["wine_rack", 30, 1, 0], ["wine_rack", 34, 1, 0], ["wine_rack", 37, 1, 0], ["wine_rack", 31, 7, 0], ["barrel", 38, 6, 0],
            ["pipes", 14, 9, 0], ["debris", 26, 9, 0],
            ["old_trunk", 5, 12, 0], ["crates", 7, 14, 0], ["barrel", 16, 12, 0], ["covered_armchair", 18, 14, 0],
            ["broken_chair", 11, 15, 0],
            ["coal_pile", 25, 12, 0], ["coal_pile", 38, 13, 0], ["woodpile", 30, 15, 0], ["barrel", 41, 15, 0],
        ],
        "stairs": [
            {"name": "Cellar Stairs", "a": [5, 7], "a_land": [6, 7], "b": [5, 1], "b_land": [5, 2], "style": "stairs"},
            {"name": "Keg Drop", "a": [48, 14], "a_land": [47, 14], "b": [41, 1], "b_land": [41, 2], "style": "hatch"},
        ],
    },
    "harbor": {
        "size": [50, 17],
        "rooms": [
            broom("bonded_vaults", "Bonded Vaults", "stone", "cellar", [[5, 1, 14, 7]]),
            broom("boiler_room", "Boiler Room", "stone", "cellar", [[20, 1, 9, 7]], lit=True),
            broom("ice_house", "Ice House", "stone", "cellar", [[30, 1, 16, 7]]),
            broom("tunnel", "Smugglers' Tunnel", "dirt", "hall", [[5, 9, 41, 2]]),
            broom("rum_store", "Rum Store", "stone", "cellar", [[5, 12, 18, 4]]),
            broom("tide_cistern", "Tide Cistern", "stone", "cellar", [[24, 12, 22, 4]]),
        ],
        "doors": [[10, 8], [24, 8], [38, 8], [19, 4], [29, 4], [12, 11], [34, 11], [23, 13]],
        "furniture": [
            ["barrel", 5, 1, 0], ["wine_rack", 9, 1, 0], ["storage_shelf", 13, 1, 0], ["barrel", 17, 1, 0], ["barrel", 18, 1, 0],
            ["crates", 12, 4, 0], ["keg_rack", 15, 6, 0],
            ["boiler", 23, 1, 0], ["coal_pile", 20, 5, 0], ["pipes", 25, 7, 0], ["water_tank", 27, 1, 0],
            ["storage_shelf", 30, 1, 0], ["crates", 34, 1, 0], ["barrel", 38, 1, 0], ["water_tank", 40, 5, 0], ["crates", 31, 6, 0],
            ["pipes", 14, 9, 0], ["debris", 30, 9, 0],
            ["barrel", 5, 12, 0], ["barrel", 6, 12, 0], ["keg_rack", 6, 15, 0], ["crates", 16, 12, 0], ["old_trunk", 19, 15, 0],
            ["water_tank", 26, 12, 0], ["water_tank", 40, 13, 0], ["debris", 30, 13, 0], ["boards", 36, 14, 0],
        ],
        "stairs": [
            {"name": "Warehouse Stairs", "a": [5, 12], "a_land": [6, 12], "b": [5, 7], "b_land": [6, 7], "style": "stairs"},
            {"name": "Chandlery Stairs", "a": [45, 13], "a_land": [45, 14], "b": [45, 1], "b_land": [45, 2], "style": "stairs"},
        ],
    },
}

# ---------------------------------------------------------------------------
# Upper floors (revision 6). Coordinates are local to the floor; it is placed
# below everything else (main floor, basement) with the same void gap, so the
# levels never share walls, light or line of sight. Rooms get "level": 1.
# Each staircase: "top" is the cell on the upper floor (+ its landing), "main"
# the cell on the main floor. Every flight sits in a corner of its room, its
# steps running into a wall, so the two-cell flight stays inside the room.


def uroom(rid, name, floor, kind, rects, lit=False):
    r = room(rid, name, floor, kind, rects, lit=lit)
    r["level"] = 1
    return r


UPPERS = {
    "ashgrove": {
        "size": [44, 19],
        "rooms": [
            uroom("attic_landing", "Attic Landing", "wood_light", "hall", [[5, 8, 34, 3]], lit=True),
            uroom("nursery", "Nursery", "carpet_blue", "bedroom", [[5, 1, 10, 6]]),
            uroom("sewing_room", "Sewing Room", "carpet_green", "study", [[16, 1, 10, 6]]),
            uroom("attic_store", "Attic Store", "wood_dark", "storage", [[27, 1, 12, 6]]),
            uroom("box_room", "Box Room", "wood_light", "storage", [[5, 12, 8, 6]]),
            uroom("maids_room", "Maid's Room", "wood_light", "bedroom", [[14, 12, 8, 6]]),
            uroom("lumber_attic", "Lumber Attic", "wood_dark", "shed", [[23, 12, 16, 6]]),
        ],
        "doors": [[10, 7], [21, 7], [32, 7], [15, 4], [26, 4], [8, 11], [17, 11], [30, 11], [13, 15], [22, 15]],
        "furniture": [
            ["bed_single", 5, 1, 0], ["rug_round", 9, 2, 0], ["chair", 8, 1, 0], ["trunk", 12, 1, 0], ["dresser", 5, 6, 0],
            ["desk", 18, 1, 0], ["chair", 19, 3, 2], ["cabinet", 22, 1, 0], ["storage_shelf", 16, 6, 0],
            ["covered_armchair", 23, 5, 0], ["wall_mirror", 24, 1, 0],
            ["crates", 27, 1, 0], ["old_trunk", 30, 1, 0], ["covered_sofa", 33, 1, 0], ["storage_shelf", 36, 6, 0],
            ["debris", 29, 4, 0], ["broken_chair", 35, 4, 0],
            ["rug_rect", 12, 8, 0], ["candelabra", 5, 8, 0], ["wall_mirror", 24, 8, 0], ["side_table", 27, 10, 0],
            ["trunk", 5, 12, 0], ["crates", 10, 12, 0], ["bed_single", 5, 14, 0], ["barrel", 12, 17, 0],
            ["bed_single", 19, 12, 0], ["nightstand", 21, 12, 0], ["washbasin", 14, 12, 0], ["wall_mirror", 14, 17, 0],
            ["dresser", 17, 17, 0],
            ["woodpile", 24, 12, 0], ["water_tank", 36, 12, 0], ["crates", 33, 15, 0], ["boards", 27, 14, 0],
            ["covered_armchair", 26, 16, 0], ["barrel", 38, 17, 0], ["old_trunk", 31, 17, 0],
        ],
        "stairs": [
            {"name": "Attic Stairs", "main": [38, 7], "main_land": [38, 8], "top": [38, 10], "top_land": [37, 10]},
        ],
    },
    "blackwood": {
        "size": [52, 22],
        "rooms": [
            uroom("long_gallery", "Upper Gallery", "carpet_red", "hall", [[5, 9, 42, 3]], lit=True),
            uroom("boudoir", "Lady's Boudoir", "carpet_red", "bedroom", [[5, 1, 10, 7]]),
            uroom("blue_room", "Blue Guest Room", "carpet_blue", "bedroom", [[16, 1, 10, 7]]),
            uroom("sewing_room", "Sewing Room", "wood_light", "study", [[27, 1, 8, 7]]),
            uroom("linen_room", "Linen Room", "wood_light", "storage", [[36, 1, 11, 7]]),
            uroom("rose_room", "Rose Guest Room", "carpet_green", "bedroom", [[5, 13, 13, 8]]),
            uroom("governess_room", "Governess's Room", "wood_dark", "bedroom", [[19, 13, 13, 8]]),
            uroom("library_gallery", "Library Gallery", "wood_dark", "study", [[33, 13, 14, 8]]),
        ],
        "doors": [[10, 8], [21, 8], [31, 8], [41, 8], [15, 4], [26, 4], [35, 4], [11, 12], [25, 12], [39, 12],
                  [18, 16], [32, 16]],
        "furniture": [
            ["bed_double", 10, 1, 0], ["nightstand", 9, 1, 0], ["nightstand", 13, 1, 0], ["dresser", 5, 7, 0],
            ["wall_mirror", 7, 7, 0], ["armchair", 12, 5, 0],
            ["bed_double", 19, 1, 0], ["nightstand", 18, 1, 0], ["nightstand", 22, 1, 0], ["wardrobe", 16, 7, 0],
            ["dresser", 23, 7, 0], ["chair", 24, 1, 0],
            ["desk", 28, 1, 0], ["chair", 29, 3, 2], ["cabinet", 32, 1, 0], ["covered_armchair", 27, 6, 0],
            ["storage_shelf", 32, 7, 0],
            ["storage_shelf", 37, 1, 0], ["storage_shelf", 41, 1, 0], ["wash_tub", 45, 1, 0], ["cabinet", 36, 7, 0],
            ["trunk", 44, 7, 0], ["boards", 39, 5, 0],
            ["grandfather_clock", 5, 9, 0], ["rug_rect", 14, 9, 0], ["rug_rect", 32, 9, 0], ["wall_mirror", 27, 9, 0],
            ["candelabra", 46, 9, 0], ["potted_plant", 46, 11, 0], ["pew", 16, 11, 0],
            ["bed_double", 5, 14, 0], ["nightstand", 8, 14, 0], ["wardrobe", 5, 20, 0], ["dresser", 13, 13, 0],
            ["rug_round", 10, 16, 0], ["armchair", 15, 19, 0],
            ["bed_single", 29, 13, 0], ["nightstand", 31, 13, 0], ["desk", 20, 13, 0], ["chair", 21, 15, 2],
            ["bookshelf", 22, 20, 0], ["trunk", 28, 20, 0], ["washbasin", 19, 20, 0],
            ["bookshelf", 33, 13, 0], ["bookshelf", 41, 13, 0], ["bookshelf", 36, 20, 0], ["bookshelf", 40, 20, 0],
            ["desk", 37, 16, 0], ["chair", 38, 18, 2], ["armchair", 44, 16, 0], ["floor_lamp", 46, 13, 0],
        ],
        "stairs": [
            {"name": "Back Stairs", "main": [20, 5], "main_land": [20, 6], "top": [5, 1], "top_land": [5, 2]},
            {"name": "Library Stair", "main": [46, 28], "main_land": [46, 27], "top": [46, 20], "top_land": [46, 19]},
        ],
    },
    "hollow_lane": {
        "size": [48, 20],
        "rooms": [
            uroom("upstairs_hall", "Upstairs Hall", "wood_dark", "hall", [[5, 8, 26, 3]], lit=True),
            uroom("farmhand_room", "Farmhand's Room", "wood_light", "bedroom", [[5, 1, 8, 6]]),
            uroom("sewing_room", "Sewing Room", "carpet_green", "study", [[14, 1, 8, 6]]),
            uroom("spare_room", "Spare Room", "wood_light", "bedroom", [[23, 1, 8, 6]]),
            uroom("grandmother_room", "Grandmother's Room", "carpet_red", "bedroom", [[5, 12, 10, 7]]),
            uroom("attic", "Attic", "wood_dark", "storage", [[16, 12, 15, 7]]),
            uroom("hayloft", "Hayloft", "dirt", "shed", [[32, 1, 11, 18]]),
        ],
        "doors": [[9, 7], [18, 7], [27, 7], [13, 4], [22, 4], [10, 11], [23, 11], [15, 15], [31, 9], [31, 15]],
        "furniture": [
            ["bed_single", 5, 1, 0], ["trunk", 11, 1, 0], ["chair", 8, 3, 0], ["dresser", 5, 6, 0],
            ["desk", 15, 1, 0], ["chair", 16, 3, 2], ["cabinet", 20, 1, 0], ["covered_armchair", 14, 5, 0],
            ["wall_mirror", 20, 6, 0],
            ["bed_single", 29, 1, 0], ["nightstand", 28, 1, 0], ["covered_sofa", 23, 1, 0], ["broken_chair", 24, 6, 0],
            ["debris", 25, 4, 0],
            ["rug_rect", 12, 8, 0], ["side_table", 30, 8, 0], ["candelabra", 20, 10, 0],
            ["bed_single", 5, 12, 0], ["nightstand", 7, 12, 0], ["armchair", 12, 17, 0], ["wardrobe", 5, 18, 0],
            ["dresser", 11, 12, 0],
            ["crates", 16, 12, 0], ["old_trunk", 19, 12, 0], ["covered_armchair", 26, 12, 0], ["debris", 20, 15, 0],
            ["storage_shelf", 16, 18, 0], ["water_tank", 28, 17, 0], ["boards", 23, 16, 0],
            ["hay", 33, 1, 0], ["hay", 37, 1, 0], ["hay", 40, 4, 0], ["hay", 34, 12, 0], ["hay", 40, 16, 0],
            ["crates", 36, 7, 0], ["barrel", 42, 10, 0], ["woodpile", 38, 18, 0],
        ],
        "stairs": [
            {"name": "Farmhouse Stairs", "main": [14, 25], "main_land": [14, 24], "top": [5, 10], "top_land": [6, 10]},
        ],
    },
    "evangeline": {
        "size": [48, 22],
        "rooms": [
            uroom("bell_tower", "Bell Tower", "stone", "chapel", [[5, 1, 10, 9]]),
            uroom("organ_loft", "Organ Loft", "wood_dark", "chapel", [[16, 1, 15, 6]], lit=True),
            uroom("curate_room", "Curate's Room", "carpet_blue", "bedroom", [[32, 1, 11, 6]]),
            uroom("clerestory", "Clerestory Walk", "stone", "hall", [[16, 8, 27, 3]]),
            uroom("linen_press", "Linen Press", "wood_light", "storage", [[16, 12, 8, 6]]),
            uroom("housekeeper_room", "Housekeeper's Room", "carpet_green", "bedroom", [[25, 12, 8, 6]]),
            uroom("rectory_landing", "Rectory Landing", "wood_dark", "hall", [[34, 12, 9, 8]], lit=True),
        ],
        "doors": [[15, 5], [15, 9], [31, 3], [23, 7], [37, 7], [20, 11], [24, 14], [28, 11], [33, 14], [38, 11]],
        "furniture": [
            ["old_trunk", 5, 1, 0], ["broken_chair", 8, 4, 0], ["debris", 9, 6, 0], ["boards", 6, 8, 0],
            ["storage_shelf", 11, 1, 0], ["candelabra", 5, 9, 0], ["barrel", 12, 8, 0],
            ["piano", 22, 1, 0], ["pew", 18, 4, 0], ["pew", 25, 4, 0], ["candelabra", 30, 1, 0], ["chair", 23, 3, 0],
            ["bed_single", 41, 1, 0], ["nightstand", 40, 1, 0], ["desk", 33, 1, 0], ["chair", 34, 3, 2],
            ["wardrobe", 38, 6, 0], ["wall_mirror", 32, 6, 0],
            ["pew", 25, 8, 0], ["candelabra", 42, 8, 0], ["rug_rect", 30, 8, 0], ["potted_plant", 42, 10, 0],
            ["storage_shelf", 16, 12, 0], ["cabinet", 16, 17, 0], ["wash_tub", 21, 16, 0], ["trunk", 22, 12, 0],
            ["bed_single", 29, 16, 1], ["nightstand", 32, 15, 0], ["dresser", 25, 12, 0], ["washbasin", 31, 12, 0],
            ["chair", 26, 16, 0],
            ["grandfather_clock", 42, 12, 0], ["side_table", 34, 12, 0], ["potted_plant", 42, 19, 0], ["rug_rect", 37, 15, 0],
            ["bookshelf", 39, 12, 0],
        ],
        "stairs": [
            {"name": "Loft Stairs", "main": [16, 4], "main_land": [16, 5], "top": [16, 1], "top_land": [16, 2]},
            {"name": "Rectory Stairs", "main": [32, 27], "main_land": [32, 26], "top": [34, 19], "top_land": [34, 18]},
        ],
    },
    "marrow_street": {
        "size": [40, 20],
        "rooms": [
            uroom("landing", "First-Floor Landing", "parquet", "hall", [[4, 8, 32, 3]], lit=True),
            uroom("master", "Master Bedroom", "carpet_red", "bedroom", [[4, 1, 12, 6]]),
            uroom("dressing_room", "Dressing Room", "carpet_blue", "bedroom", [[17, 1, 6, 6]]),
            uroom("nursery", "Nursery", "carpet_green", "bedroom", [[24, 1, 12, 6]]),
            uroom("upper_study", "Upstairs Study", "wood_dark", "study", [[4, 12, 11, 7]]),
            uroom("water_closet", "Water Closet", "tile_white", "bathroom", [[16, 12, 6, 7]]),
            uroom("garret", "Maid's Garret", "wood_light", "bedroom", [[23, 12, 13, 7]]),
        ],
        "doors": [[10, 7], [20, 7], [30, 7], [16, 4], [23, 4], [9, 11], [19, 11], [29, 11], [15, 15], [22, 15]],
        "furniture": [
            ["bed_double", 8, 1, 0], ["nightstand", 7, 1, 0], ["nightstand", 11, 1, 0], ["wardrobe", 4, 1, 0],
            ["dresser", 13, 6, 0], ["armchair", 4, 5, 0], ["fireplace", 13, 1, 0],
            ["wardrobe", 17, 1, 0], ["wall_mirror", 21, 1, 0], ["dresser", 17, 6, 0],
            ["bed_single", 34, 1, 0], ["rug_round", 27, 2, 0], ["chair", 25, 1, 0], ["trunk", 32, 6, 0], ["dresser", 24, 6, 0],
            ["rug_rect", 12, 8, 0], ["rug_rect", 23, 8, 0], ["grandfather_clock", 35, 8, 0], ["side_table", 35, 10, 0],
            ["candelabra", 25, 10, 0],
            ["bookshelf", 4, 12, 0], ["bookshelf", 11, 12, 0], ["desk", 6, 15, 0], ["chair", 7, 17, 2], ["armchair", 11, 17, 0],
            ["floor_lamp", 14, 18, 0],
            ["bathtub", 16, 12, 0], ["toilet", 21, 18, 0], ["washbasin", 21, 12, 0], ["wall_mirror", 18, 18, 0],
            ["bed_single", 34, 12, 0], ["bed_single", 31, 12, 0], ["nightstand", 33, 12, 0], ["trunk", 23, 18, 0],
            ["washbasin", 35, 18, 0], ["broken_chair", 27, 17, 0], ["wash_tub", 25, 12, 0],
        ],
        "stairs": [
            {"name": "Main Stairs", "main": [4, 9], "main_land": [4, 10], "top": [4, 10], "top_land": [5, 10]},
        ],
    },
    "tavern": {
        "size": [44, 20],
        "rooms": [
            uroom("guest_corridor", "Guest Corridor", "wood_dark", "hall", [[5, 8, 37, 3]], lit=True),
            uroom("room_one", "Guest Room One", "wood_light", "bedroom", [[5, 1, 8, 6]]),
            uroom("room_two", "Guest Room Two", "carpet_blue", "bedroom", [[14, 1, 8, 6]]),
            uroom("room_three", "Guest Room Three", "carpet_red", "bedroom", [[23, 1, 8, 6]]),
            uroom("washroom", "Washroom", "tile_white", "bathroom", [[32, 1, 10, 6]]),
            uroom("room_four", "Guest Room Four", "carpet_green", "bedroom", [[5, 12, 14, 7]]),
            uroom("linen_store", "Linen Store", "wood_light", "storage", [[20, 12, 7, 7]]),
            uroom("quarters", "Innkeeper's Quarters", "carpet_red", "bedroom", [[28, 12, 14, 7]]),
        ],
        "doors": [[9, 7], [18, 7], [27, 7], [36, 7], [13, 5], [22, 5], [31, 5], [10, 11], [23, 11], [34, 11],
                  [19, 15], [27, 15]],
        "furniture": [
            ["bed_single", 5, 1, 0], ["nightstand", 7, 1, 0], ["wardrobe", 10, 1, 0], ["dresser", 5, 6, 0],
            ["bed_single", 14, 1, 0], ["nightstand", 16, 1, 0], ["wardrobe", 19, 1, 0], ["dresser", 20, 6, 0],
            ["bed_double", 27, 1, 0], ["nightstand", 26, 1, 0], ["nightstand", 30, 1, 0], ["trunk", 23, 6, 0],
            ["bathtub", 39, 1, 0], ["toilet", 41, 6, 0], ["washbasin", 33, 1, 0], ["wall_mirror", 34, 1, 0],
            ["wash_tub", 32, 3, 0],
            ["rug_rect", 14, 8, 0], ["rug_rect", 28, 8, 0], ["candelabra", 24, 8, 0], ["side_table", 41, 8, 0],
            ["potted_plant", 41, 10, 0],
            ["bed_double", 5, 13, 0], ["nightstand", 8, 13, 0], ["wardrobe", 14, 12, 0], ["dresser", 16, 18, 0],
            ["armchair", 11, 16, 0],
            ["storage_shelf", 20, 12, 0], ["cabinet", 25, 12, 0], ["trunk", 20, 18, 0], ["crates", 24, 17, 0],
            ["bed_double", 36, 12, 0], ["nightstand", 35, 12, 0], ["nightstand", 39, 12, 0], ["desk", 29, 12, 0],
            ["chair", 30, 14, 2], ["wardrobe", 28, 18, 0], ["wall_mirror", 32, 18, 0], ["candelabra", 41, 12, 0],
            ["trunk", 34, 18, 0], ["rug_rect", 33, 15, 0],
        ],
        "stairs": [
            {"name": "Inn Stairs", "main": [5, 26], "main_land": [6, 26], "top": [5, 10], "top_land": [6, 10]},
            {"name": "Back Stairs", "main": [41, 26], "main_land": [40, 26], "top": [41, 18], "top_land": [40, 18]},
        ],
    },
    "harbor": {
        "size": [50, 16],
        "rooms": [
            uroom("loft", "Warehouse Loft", "wood_dark", "storage", [[5, 1, 18, 13]]),
            uroom("lodging", "Harbour Master's Lodging", "carpet_red", "bedroom", [[24, 1, 10, 6]]),
            uroom("washroom", "Washroom", "tile_white", "bathroom", [[35, 1, 5, 6]]),
            uroom("lamp_room", "Signal Lamp Room", "wood_light", "study", [[41, 1, 8, 6]], lit=True),
            uroom("upper_gallery", "Upper Gallery", "wood_dark", "hall", [[24, 8, 25, 2]]),
            uroom("chart_room", "Chart Room", "carpet_green", "study", [[24, 11, 12, 4]]),
            uroom("bunkroom", "Clerks' Bunkroom", "wood_light", "bedroom", [[37, 11, 12, 4]]),
        ],
        "doors": [[23, 8], [23, 3], [28, 7], [34, 5], [40, 5], [44, 7], [30, 10], [36, 12], [42, 10]],
        "furniture": [
            ["crates", 5, 1, 0], ["crates", 8, 1, 0], ["fishing_net", 12, 2, 0], ["rope_coil", 16, 1, 0], ["old_trunk", 19, 1, 0],
            ["covered_sofa", 6, 6, 0], ["crates", 14, 8, 0], ["storage_shelf", 5, 13, 0], ["barrel", 18, 10, 0],
            ["debris", 10, 10, 0], ["boards", 16, 12, 0],
            ["bed_double", 30, 1, 0], ["nightstand", 29, 1, 0], ["wardrobe", 24, 1, 0], ["dresser", 24, 6, 0], ["chair", 27, 4, 0],
            ["bathtub", 35, 1, 0], ["washbasin", 39, 1, 0], ["wall_mirror", 37, 1, 0], ["toilet", 39, 6, 0],
            ["desk", 44, 2, 0], ["chair", 45, 4, 2], ["floor_lamp", 48, 1, 0], ["bookshelf", 41, 1, 0], ["trunk", 47, 6, 0],
            ["candelabra", 33, 9, 0], ["candelabra", 48, 9, 0],
            ["desk", 29, 12, 0], ["bookshelf", 32, 11, 0], ["chair", 30, 14, 2], ["floor_lamp", 35, 14, 0], ["cabinet", 26, 11, 0],
            ["bed_single", 37, 13, 1], ["bed_single", 44, 13, 1], ["trunk", 47, 11, 0], ["nightstand", 41, 14, 0],
            ["wall_mirror", 39, 11, 0],
        ],
        "stairs": [
            {"name": "Loft Stairs", "main": [22, 5], "main_land": [22, 6], "top": [22, 13], "top_land": [22, 12]},
            {"name": "Office Stairs", "main": [33, 5], "main_land": [33, 6], "top": [24, 14], "top_land": [24, 13]},
        ],
    },
}

# Neglect: some rooms are lived in and kept, others forgotten. Outdoor rooms have none.
CONDITIONS = {
    "ashgrove": {"kitchen": "kept", "living": "kept", "guest": "kept", "hallway": "worn", "dining": "worn", "master": "worn",
                 "study": "neglected", "bathroom": "neglected", "shed": "neglected", "root_cellar": "neglected",
                 "cellar_store": "abandoned", "cold_store": "abandoned", "coal_hole": "neglected"},
    "blackwood": {"foyer": "kept", "dining": "kept", "master": "kept", "kitchen": "kept", "ballroom": "worn", "library": "worn",
                  "gallery": "worn", "bathroom": "worn", "conservatory": "neglected", "nursery": "abandoned",
                  "servants_hall": "neglected", "pantry": "neglected", "wine_cellar": "neglected",
                  "servants_quarters": "abandoned", "boiler_room": "worn", "undercroft": "neglected",
                  "old_laundry": "abandoned", "strongroom": "neglected", "coal_store": "abandoned"},
    "hollow_lane": {"kitchen": "kept", "parlor": "kept", "corridor": "worn", "bedroom": "worn", "mudroom": "worn",
                    "bathroom": "worn", "kids_room": "neglected", "cellar": "neglected", "barn": "neglected",
                    "root_store": "neglected", "old_workshop": "worn", "pump_room": "abandoned",
                    "cellar_passage": "neglected", "feed_store": "abandoned", "well_room": "abandoned"},
    "evangeline": {"rector_study": "kept", "kitchen": "kept", "nave": "worn", "chancel": "worn", "refectory": "worn",
                   "bedroom": "worn", "vestry": "neglected", "crypt": "neglected", "bathroom": "neglected",
                   "undercroft": "abandoned", "parish_archive": "neglected", "boiler_house": "worn", "ossuary": "abandoned",
                   "service_tunnel": "neglected", "cistern": "abandoned", "church_stores": "neglected"},
    "marrow_street": {"front_parlor": "kept", "entry": "kept", "dining": "kept", "kitchen": "kept", "stair_hall": "worn",
                      "bedroom": "worn", "bathroom": "worn", "drawing_room": "neglected", "scullery": "neglected",
                      "box_room": "abandoned", "coal_shed": "neglected", "coal_cellar": "abandoned", "utility_room": "worn",
                      "wine_store": "neglected", "basement_passage": "neglected", "laundry": "abandoned",
                      "lumber_room": "abandoned"},
}

# A few signs of neglect on the main floors (validated like everything else).
MAIN_NEGLECT = {
    "ashgrove": [["debris", 32, 11, 0], ["boards", 19, 3, 0]],
    "blackwood": [["broken_chair", 43, 8, 0], ["debris", 40, 16, 0], ["boards", 25, 2, 0]],
    "hollow_lane": [["debris", 37, 7, 0], ["boards", 6, 16, 0]],
    "evangeline": [["covered_armchair", 7, 6, 0], ["debris", 18, 10, 0]],
    "marrow_street": [["debris", 33, 22, 0], ["boards", 6, 17, 0]],
}


# Upper floors and the two newer locations.
CONDITIONS["ashgrove"].update({"attic_landing": "worn", "nursery": "abandoned", "sewing_room": "neglected",
                               "attic_store": "abandoned", "box_room": "neglected", "maids_room": "worn",
                               "lumber_attic": "abandoned"})
CONDITIONS["blackwood"].update({"long_gallery": "kept", "boudoir": "worn", "blue_room": "kept", "sewing_room": "neglected",
                                "linen_room": "worn", "rose_room": "worn", "governess_room": "abandoned",
                                "library_gallery": "neglected"})
CONDITIONS["hollow_lane"].update({"upstairs_hall": "worn", "farmhand_room": "neglected", "sewing_room": "worn",
                                  "spare_room": "abandoned", "grandmother_room": "kept", "attic": "abandoned",
                                  "hayloft": "neglected"})
CONDITIONS["evangeline"].update({"bell_tower": "abandoned", "organ_loft": "worn", "curate_room": "neglected",
                                 "clerestory": "neglected", "linen_press": "worn", "housekeeper_room": "kept",
                                 "rectory_landing": "worn"})
CONDITIONS["marrow_street"].update({"landing": "kept", "master": "kept", "dressing_room": "worn", "nursery": "abandoned",
                                    "upper_study": "neglected", "water_closet": "worn", "garret": "neglected"})
CONDITIONS["tavern"] = {"kitchen": "worn", "pantry": "worn", "brewhouse": "neglected", "stables": "neglected",
                        "back_passage": "worn", "common_room": "kept", "taproom": "kept", "snug": "worn", "office": "kept",
                        "beer_cellar": "worn", "boiler_room": "worn", "wine_vault": "neglected", "cellar_passage": "neglected",
                        "smugglers_hold": "abandoned", "coal_store": "abandoned", "guest_corridor": "worn",
                        "room_one": "kept", "room_two": "worn", "room_three": "neglected", "washroom": "worn",
                        "room_four": "abandoned", "linen_store": "neglected", "quarters": "kept"}
CONDITIONS["harbor"] = {"warehouse": "neglected", "salting_house": "worn", "cooperage": "neglected", "harbour_office": "kept",
                        "customs_hall": "worn", "mess": "kept", "chandlery": "worn", "net_shed": "abandoned",
                        "bonded_vaults": "neglected", "boiler_room": "worn", "ice_house": "abandoned", "tunnel": "abandoned",
                        "rum_store": "neglected", "tide_cistern": "abandoned", "loft": "abandoned", "lodging": "kept",
                        "washroom": "worn", "lamp_room": "worn", "upper_gallery": "worn", "chart_room": "neglected",
                        "bunkroom": "neglected"}
MAIN_NEGLECT["tavern"] = [["debris", 36, 3, 0], ["boards", 26, 10, 0]]
MAIN_NEGLECT["harbor"] = [["debris", 49, 13, 0], ["boards", 8, 11, 0]]


def _attach_level(h, extra, oy, prefix):
    """Append another floor's rooms/doors/furniture to the house, shifted down by oy."""
    taken = {x["id"] for x in h["rooms"]}
    for r in extra["rooms"]:
        r = dict(r)
        cond = CONDITIONS.get(h["id"], {}).get(r["id"])
        r["id"] = r["id"] if r["id"] not in taken else prefix + r["id"]
        r["rects"] = [[x, y + oy, rw, rh] for x, y, rw, rh in r["rects"]]
        if cond:
            r["condition"] = cond
        h["rooms"].append(r)
    h["doors"] = h["doors"] + [[x, y + oy] for x, y in extra["doors"]]
    h["furniture"] = h["furniture"] + [[t, x, y + oy, rot] for t, x, y, rot in extra["furniture"]]
    h["size"] = [max(h["size"][0], extra["size"][0]), oy + extra["size"][1]]


def attach_levels(h):
    """Main floor (level 0), then the basement (-1) and the upper floor (1) further down the world."""
    for r in h["rooms"]:
        r.setdefault("level", 0)
        cond = CONDITIONS.get(h["id"], {}).get(r["id"])
        if cond:
            r["condition"] = cond
    h["furniture"] = h["furniture"] + MAIN_NEGLECT.get(h["id"], [])
    h["stairs"] = []
    b = BASEMENTS.get(h["id"])
    if b:
        oy = h["size"][1] + FLOOR_GAP
        _attach_level(h, b, oy, "basement_")
        # Basement stairs: "a" on the main floor, "b" below.
        h["stairs"] += [{"name": st["name"], "style": st["style"], "a": st["a"], "a_land": st["a_land"],
                         "b": [st["b"][0], st["b"][1] + oy], "b_land": [st["b_land"][0], st["b_land"][1] + oy]}
                        for st in b["stairs"]]
    u = UPPERS.get(h["id"])
    if u:
        oy = h["size"][1] + FLOOR_GAP
        _attach_level(h, u, oy, "upper_")
        # Upper stairs: "a" is always the higher floor (drawn going down), "b" the main floor.
        h["stairs"] += [{"name": st["name"], "style": st.get("style", "stairs"),
                         "a": [st["top"][0], st["top"][1] + oy], "a_land": [st["top_land"][0], st["top_land"][1] + oy],
                         "b": st["main"], "b_land": st["main_land"]}
                        for st in u["stairs"]]


for _h in HOUSES:
    attach_levels(_h)


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
    links = {}
    door_adj = {(x + dx, y + dy) for x, y in h["doors"] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
    for st in h.get("stairs", []):
        for cell_k, land_k in (("a", "b_land"), ("b", "a_land")):
            c, land = tuple(st[cell_k]), tuple(st[land_k])
            links[c] = land
        for k in ("a", "a_land", "b", "b_land"):
            c = tuple(st[k])
            if c not in walk:
                problems.append(f"stair {st['name']} {k} {c} not walkable")
            if c in door_adj:
                problems.append(f"stair {st['name']} {k} {c} touches a doorway")
        for k, land in (("a", "a_land"), ("b", "b_land")):
            if abs(st[k][0] - st[land][0]) + abs(st[k][1] - st[land][1]) != 1:
                problems.append(f"stair {st['name']}: landing {land} not beside {k}")
        if (h["id"], st["name"]) not in LEGACY_STAIRS:
            problems += _check_flight(h, grid, st, solid, door_adj)
    start = tuple(h["spawn"])
    if start not in walk:
        problems.append("spawn not walkable")
        return problems
    seen = {start}
    stack = [start]
    while stack:
        x, y = stack.pop()
        nexts = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        if (x, y) in links:
            nexts.append(links[(x, y)])
        for n in nexts:
            if n in walk and n not in seen:
                seen.add(n)
                stack.append(n)
    lost = walk - seen
    if lost:
        problems.append(f"{len(lost)} unreachable walkable cells e.g. {sorted(lost)[:6]}")
    # Dead ends: rooms with a single doorway (outdoor-open boundaries count as exits).
    # One is tolerated (the game's own check allows it): an outdoor nook such as a moored boat.
    dead = []
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
            dead.append(r)
            if not (r["outdoor"] and open_edges):
                problems.append(f"dead end room: {r['id']} ({exits} doors)")
    if len(dead) > 1:
        problems.append(f"{len(dead)} dead-end rooms: {[r['id'] for r in dead]}")
    return problems


# The original basement stairs predate the corner rule below.
LEGACY_STAIRS = {("ashgrove", "Cellar Stairs"), ("ashgrove", "Garden Hatch"), ("blackwood", "Cellar Stairs"),
                 ("blackwood", "Servants' Stairs"), ("hollow_lane", "Cellar Stairs"), ("hollow_lane", "Barn Trapdoor"),
                 ("evangeline", "Crypt Stairs"), ("evangeline", "Kitchen Stairs"), ("marrow_street", "Coal Chute"),
                 ("marrow_street", "Basement Stairs")}


def _check_flight(h, grid, st, solid, door_adj):
    """Mirror of HouseMap's two-cell flight: the steps run into a wall, the flight's second
    cell is the sideways neighbour (same rule and order as the game), and a staircase sits
    in a corner. Nothing is placed on the flight or its landings, and no doorway touches them."""
    w, ht = h["size"]
    out = []
    covered = set()
    for t, x, y, rot in h["furniture"]:
        fw, fh, _ = FURN_SIZES[t]
        if rot % 2 == 1:
            fw, fh = fh, fw
        covered |= {(xx, yy) for xx in range(x, x + fw) for yy in range(y, y + fh)}

    def at(c):
        return grid[c[1]][c[0]] if 0 <= c[0] < w and 0 <= c[1] < ht else None

    for side in ("a", "b"):
        c, land = tuple(st[side]), tuple(st[side + "_land"])
        dv = (c[0] - land[0], c[1] - land[1])
        perp = (dv[1], dv[0])
        rid = at(c)
        if at((c[0] + dv[0], c[1] + dv[1])) != "#":
            out.append(f"stair {st['name']} {side}: steps do not run into a wall")
        wide = None
        for cand in ((c[0] + perp[0], c[1] + perp[1]), (c[0] - perp[0], c[1] - perp[1])):
            cl = (cand[0] - dv[0], cand[1] - dv[1])
            if at(cand) == rid and cand not in solid and at(cl) == rid and cl not in solid:
                wide = cand
                break
        cells = [c, land]
        if wide:
            cells += [wide, (wide[0] - dv[0], wide[1] - dv[1])]
            if at((wide[0] + dv[0], wide[1] + dv[1])) != "#":
                out.append(f"stair {st['name']} {side}: second step cell {wide} sticks out from the wall")
        elif st.get("style", "stairs") == "stairs":
            out.append(f"stair {st['name']} {side}: no room for a two-cell flight")
        for cc in cells:
            if cc in covered:
                out.append(f"stair {st['name']} {side}: furniture on {cc}")
            if cc in door_adj:
                out.append(f"stair {st['name']} {side}: {cc} touches a doorway")
        if st.get("style", "stairs") == "stairs" and wide:
            corner = at((2 * c[0] - wide[0], 2 * c[1] - wide[1])) == "#" or at((2 * wide[0] - c[0], 2 * wide[1] - c[1])) == "#"
            if not corner:
                out.append(f"stair {st['name']} {side}: not in a corner")
    return out


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
