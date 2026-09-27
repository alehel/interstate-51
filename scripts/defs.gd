class_name Defs
## Static game data: weapons, vehicles, campaign.

enum Team { PLAYER = 0, ENEMY = 1, NEUTRAL = 2 }

const WEAPONS := {
	"mg30": {
		"name": ".30 Cal Browning", "kind": "gun", "slot": "gun",
		"dmg": 5.0, "rate": 11.0, "range": 260.0, "spread": 0.014, "ammo": 1000,
		"sound": "mg30_shot", "tracer": Color(1.0, 0.85, 0.45),
		"desc": "Twin air-cooled Brownings. Fast, reliable, and nobody asks where they came from.",
	},
	"mg50": {
		"name": ".50 Cal \"Thumper\"", "kind": "gun", "slot": "gun",
		"dmg": 13.0, "rate": 5.5, "range": 340.0, "spread": 0.008, "ammo": 420,
		"sound": "mg50_shot", "tracer": Color(1.0, 0.55, 0.25),
		"desc": "Salvaged off Sheriff Harlan's cruiser. Slow to talk, but it has the last word.",
	},
	"flame": {
		"name": "Dragon's Breath", "kind": "flame", "slot": "gun",
		"dmg": 42.0, "rate": 15.0, "range": 24.0, "spread": 0.0, "ammo": 300,
		"sound": "flame_loop", "tracer": Color(1.0, 0.5, 0.1),
		"desc": "A crop duster pump, a propane tank and a bad attitude. Short range. Sets things on fire.",
	},
	"rockets": {
		"name": "Zuni Rockets", "kind": "rocket", "slot": "special",
		"dmg": 65.0, "splash": 7.0, "rate": 1.4, "speed": 115.0, "range": 400.0, "ammo": 18,
		"sound": "rocket_launch", "tracer": Color(1.0, 0.7, 0.3),
		"desc": "Navy-surplus five-inch air-to-ground rockets. Mildly guided toward your locked target.",
	},
	"mines": {
		"name": "Road Mines", "kind": "mine", "slot": "special",
		"dmg": 85.0, "splash": 8.0, "rate": 1.6, "ammo": 10, "range": 0.0,
		"sound": "mine_drop", "tracer": Color(1, 0.2, 0.1),
		"desc": "Dropped out the back. Arms in a second. Ruins a tailgater's whole afternoon.",
	},
	"oil": {
		"name": "Oil Slick", "kind": "oil", "slot": "special",
		"dmg": 0.0, "rate": 1.2, "ammo": 8, "range": 0.0,
		"sound": "oil_drop", "tracer": Color(0.1, 0.1, 0.1),
		"desc": "Forty gallons of used motor oil. Anybody behind you goes for a spin.",
	},
}

## Vehicle definitions. Physics: mass (kg), power (N), top speed (m/s), grip.
## Visual: style for CarBuilder, dimensions, colors.
const CARS := {
	"merc": {
		"name": "'49 Mercury \"Black Sally\"", "style": "coupe",
		"mass": 1500.0, "power": 15500.0, "top": 54.0, "grip": 1.12,
		"armor": 110.0, "chassis": 140.0,
		"len": 5.0, "wid": 1.96, "hgt": 1.45,
		"paint": Color(0.07, 0.07, 0.08), "paint2": Color(0.07, 0.07, 0.08), "stripe": Color(0.7, 0.08, 0.06),
		"guns": 2, "roof_mount": true,
	},
	"raider": {
		"name": "Legion Raider", "style": "roadster",
		"mass": 1050.0, "power": 11500.0, "top": 50.0, "grip": 1.0,
		"armor": 32.0, "chassis": 45.0,
		"len": 4.2, "wid": 1.75, "hgt": 1.2,
		"paint": Color(0.75, 0.12, 0.08), "paint2": Color(0.9, 0.85, 0.8), "stripe": Color(1, 0.8, 0.1),
		"guns": 1, "weapons": ["mg30"],
	},
	"bruiser": {
		"name": "Legion Bruiser", "style": "sedan",
		"mass": 1850.0, "power": 15000.0, "top": 44.0, "grip": 0.98,
		"armor": 70.0, "chassis": 80.0,
		"len": 5.4, "wid": 2.02, "hgt": 1.6,
		"paint": Color(0.55, 0.57, 0.6), "paint2": Color(0.15, 0.15, 0.17), "stripe": Color(0.8, 0.1, 0.1),
		"guns": 2, "weapons": ["mg30", "mg30"],
	},
	"hauler": {
		"name": "Legion Hauler", "style": "pickup",
		"mass": 1900.0, "power": 14500.0, "top": 41.0, "grip": 0.95,
		"armor": 70.0, "chassis": 90.0,
		"len": 5.1, "wid": 2.0, "hgt": 1.8,
		"paint": Color(0.33, 0.38, 0.25), "paint2": Color(0.33, 0.38, 0.25), "stripe": Color(0.9, 0.7, 0.2),
		"guns": 0, "turret": "mg30", "weapons": [],
	},
	"cruiser": {
		"name": "Nye County Cruiser", "style": "police",
		"mass": 1750.0, "power": 15500.0, "top": 48.0, "grip": 1.0,
		"armor": 70.0, "chassis": 80.0,
		"len": 5.1, "wid": 1.98, "hgt": 1.55,
		"paint": Color(0.05, 0.05, 0.06), "paint2": Color(0.92, 0.92, 0.9), "stripe": Color(0.9, 0.75, 0.2),
		"guns": 2, "weapons": ["mg30", "mg30"],
	},
	"judge": {
		"name": "\"The Judge\" (Harlan)", "style": "police",
		"mass": 2100.0, "power": 18500.0, "top": 48.0, "grip": 1.02,
		"armor": 160.0, "chassis": 170.0,
		"len": 5.4, "wid": 2.05, "hgt": 1.6,
		"paint": Color(0.05, 0.05, 0.06), "paint2": Color(0.85, 0.72, 0.3), "stripe": Color(0.9, 0.75, 0.2),
		"guns": 2, "weapons": ["mg50", "mg50", "rockets"],
	},
	"juggernaut": {
		"name": "The Juggernaut", "style": "armored",
		"mass": 7000.0, "power": 52000.0, "top": 26.0, "grip": 1.0,
		"armor": 420.0, "chassis": 400.0,
		"len": 8.4, "wid": 2.6, "hgt": 3.1,
		"paint": Color(0.3, 0.33, 0.28), "paint2": Color(0.2, 0.22, 0.2), "stripe": Color(0.85, 0.8, 0.2),
		"guns": 0, "turret": "mg50", "weapons": [],
	},
	"duchess": {
		"name": "\"Silver Duchess\" (Vale)", "style": "caddy",
		"mass": 2400.0, "power": 24000.0, "top": 50.0, "grip": 1.05,
		"armor": 300.0, "chassis": 320.0,
		"len": 5.8, "wid": 2.08, "hgt": 1.5,
		"paint": Color(0.78, 0.8, 0.84), "paint2": Color(0.55, 0.12, 0.16), "stripe": Color(0.95, 0.8, 0.35),
		"guns": 2, "weapons": ["mg50", "mg50", "rockets", "mines"],
	},
	"hearse": {
		"name": "\"Glory Wagon\" (Preacher)", "style": "hearse",
		"mass": 2100.0, "power": 16500.0, "top": 46.0, "grip": 1.0,
		"armor": 170.0, "chassis": 200.0,
		"len": 5.9, "wid": 2.0, "hgt": 1.75,
		"paint": Color(0.12, 0.08, 0.14), "paint2": Color(0.12, 0.08, 0.14), "stripe": Color(0.85, 0.75, 0.4),
		"guns": 2, "weapons": ["mg30", "mg30"],
	},
	"supply": {
		"name": "Preacher's Supply Truck", "style": "stakebed",
		"mass": 4200.0, "power": 30000.0, "top": 30.0, "grip": 1.0,
		"armor": 170.0, "chassis": 240.0,
		"len": 7.0, "wid": 2.4, "hgt": 2.7,
		"paint": Color(0.45, 0.2, 0.12), "paint2": Color(0.3, 0.22, 0.15), "stripe": Color(0.9, 0.9, 0.8),
		"guns": 0, "weapons": [],
	},
	"wagon": {
		"name": "Ford Country Squire (Dr. Holt)", "style": "wagon",
		"mass": 1700.0, "power": 14000.0, "top": 44.0, "grip": 0.98,
		"armor": 95.0, "chassis": 130.0,
		"len": 5.2, "wid": 1.98, "hgt": 1.6,
		"paint": Color(0.22, 0.4, 0.3), "paint2": Color(0.55, 0.36, 0.2), "stripe": Color(0.9, 0.85, 0.7),
		"guns": 0, "weapons": [],
	},
	"semi": {
		"name": "\"Bessie\" (Hollis's rig)", "style": "semi",
		"mass": 8000.0, "power": 60000.0, "top": 30.0, "grip": 1.0,
		"armor": 260.0, "chassis": 320.0,
		"len": 11.5, "wid": 2.5, "hgt": 3.6,
		"paint": Color(0.1, 0.25, 0.55), "paint2": Color(0.85, 0.85, 0.82), "stripe": Color(0.95, 0.75, 0.2),
		"guns": 0, "weapons": [],
	},
	"jeep": {
		"name": "Legion Jeep", "style": "jeep",
		"mass": 1100.0, "power": 11000.0, "top": 43.0, "grip": 1.05,
		"armor": 40.0, "chassis": 55.0,
		"len": 3.6, "wid": 1.7, "hgt": 1.6,
		"paint": Color(0.36, 0.38, 0.24), "paint2": Color(0.36, 0.38, 0.24), "stripe": Color(0.9, 0.9, 0.9),
		"guns": 0, "turret": "mg30", "weapons": [],
	},
	"sedan": {
		"name": "Civilian Sedan", "style": "sedan",
		"mass": 1600.0, "power": 11000.0, "top": 38.0, "grip": 0.95,
		"armor": 40.0, "chassis": 60.0,
		"len": 5.1, "wid": 1.95, "hgt": 1.58,
		"paint": Color(0.6, 0.75, 0.8), "paint2": Color(0.95, 0.93, 0.88), "stripe": Color(0.9, 0.9, 0.9),
		"guns": 0, "weapons": [],
	},
	"junker": {
		"name": "Junker", "style": "sedan",
		"mass": 1500.0, "power": 0.0, "top": 1.0, "grip": 1.0,
		"armor": 18.0, "chassis": 30.0,
		"len": 5.1, "wid": 1.95, "hgt": 1.55,
		"paint": Color(0.45, 0.3, 0.2), "paint2": Color(0.5, 0.45, 0.35), "stripe": Color(0.5, 0.3, 0.2),
		"guns": 0, "weapons": [], "rusty": true,
	},
}

## Campaign. `unlock` = items granted before this mission's garage.
const MISSIONS := [
	{
		"id": "m1", "title": "The Boneyard", "script": "res://scripts/missions/m01_boneyard.gd",
		"briefing": ["b1_1", "b1_2", "b1_3"], "time": "afternoon", "music": "drive_boogie",
		"map": Vector2(-700, 950), "unlock": ["mg30"],
		"summary": "Meet Rosa Delgado at her salvage yard. Get reacquainted with Sally.",
	},
	{
		"id": "m2", "title": "Tonopah Junction", "script": "res://scripts/missions/m02_tonopah.gd",
		"briefing": ["b2_1", "b2_2"], "time": "noon", "music": "drive_rockabilly",
		"map": Vector2(-230, -1700), "unlock": ["rockets"],
		"summary": "Hal's truck stop is burning. Find out what Hollis left behind.",
	},
	{
		"id": "m3", "title": "Sheriff's Welcome", "script": "res://scripts/missions/m03_sheriff.gd",
		"briefing": ["b3_1", "b3_2"], "time": "dusk", "music": "drive_boogie",
		"map": Vector2(-1520, 300), "unlock": ["mines"],
		"summary": "Nye County's sheriff is waiting in the canyon. Answer his invitation.",
	},
	{
		"id": "m4", "title": "Glory Wagon", "script": "res://scripts/missions/m04_convoy.gd",
		"briefing": ["b4_1", "b4_2"], "time": "golden", "music": "drive_rockabilly",
		"map": Vector2(-2300, -300), "unlock": ["mg50"],
		"summary": "Escort Preacher's convoy from Gold Creek to the Boneyard.",
	},
	{
		"id": "m5", "title": "Chain Reaction", "script": "res://scripts/missions/m05_scientist.gd",
		"briefing": ["b5_1", "b5_2"], "time": "dawn", "music": "drive_boogie",
		"map": Vector2(-200, -1500), "unlock": ["oil", "engine_tune"],
		"summary": "A British physicist is running for her life on Highway 95.",
	},
	{
		"id": "m6", "title": "Lights Out at Mercury", "script": "res://scripts/missions/m06_depot.gd",
		"briefing": ["b6_1", "b6_2"], "time": "night", "music": "tension_night",
		"map": Vector2(1900, -600), "unlock": ["flame"],
		"summary": "Raid Vale's trucking depot at the Mercury gate and steal his records.",
	},
	{
		"id": "m7", "title": "The Silver Queen", "script": "res://scripts/missions/m07_mine.gd",
		"briefing": ["b7_1", "b7_2"], "time": "morning", "music": "drive_rockabilly",
		"map": Vector2(1700, -2150), "unlock": ["boiler_plate"],
		"summary": "Break Hollis out of the Silver Queen mine and bring him home.",
	},
	{
		"id": "m8", "title": "Broken Arrow", "script": "res://scripts/missions/m08_juggernaut.gd",
		"briefing": ["b8_1", "b8_2"], "time": "dusk", "music": "finale",
		"map": Vector2(2000, 800), "unlock": [],
		"summary": "Stop the Juggernaut before it reaches the Indian Springs airstrip.",
	},
	{
		"id": "m9", "title": "Atomic Dawn", "script": "res://scripts/missions/m09_finale.gd",
		"briefing": ["b9_1", "b9_2"], "time": "dawn", "music": "finale",
		"map": Vector2(2100, 2100), "unlock": [],
		"summary": "Vale, the Silver Duchess, and a stolen atom bomb. End it.",
	},
]

const UPGRADES := {
	"engine_tune": {"name": "Moonshiner's Tune-Up", "desc": "Preacher's mechanics reworked Sally's flathead. +12% power, +4 mph top speed."},
	"boiler_plate": {"name": "Boiler Plate Armor", "desc": "Rosa welded locomotive plate over every panel. +35% armor."},
}
