## v0.12.6 (Jacob): good, funny names for the fighters you spawn (the Duel Stone's challengers and the dev console's
## units) and for golems. An NPC gets a first name and an epithet ("Sir Reginald the Moist"); a golem's name comes from
## its id, so every screen shows the same one without sending it ("Pebbles McGee", "Lord Gravelbottom"), and a titan
## gets a grand one ("Mount Kevin").
class_name Names

const FIRST := ["Brutus", "Grizelda", "Morwen", "Tobias", "Ragnhild", "Corvin", "Ysolde", "Barnaby", "Thane", "Vesper",
	"Odalric", "Mirela", "Fenwick", "Sable", "Sir Reginald", "Dame Agatha", "Gary", "Big Steve", "Lady Crumpet",
	"Bartholomew", "Ser Pantsalot", "Grandma Hilda", "Kevin", "Duchess Noodle", "Old Man Jenkins", "Captain Wobble",
	"Brother Mildew", "Sister Gristle", "Lord Snoot", "Bjorn", "Gunther", "Pip's Cousin Pop", "Tim", "Madame Bonk",
	"Sir Clank", "Igor", "Percival", "Ethel", "Dennis", "Baron von Shin", "Fluffy", "Uncle Grumbo", "Stabitha"]
const EPITHET := ["the Moist", "the Unwashed", "the Mildly Concerning", "the Slightly Damp", "Who Bites",
	"the Overconfident", "of the Wet Socks", "the Loud", "the Surprisingly Polite", "Twice-Divorced", "the Sneezer",
	"No-Knees", "the Unready", "the Tax Collector", "the Lukewarm", "Bad-at-Dodging", "the Snack Thief",
	"of Questionable Hygiene", "the Unbathed", "Who Yells", "the Pointy", "Three-Toes", "the Dramatic",
	"the Late", "Breaker of Chairs", "the Absolutely Sure", "Who Forgot Why", "the Crunchy", "the Soggy",
	"the Magnificent (Self-Titled)", "the Second-Best", "Smells-of-Cheese", "the Twitchy", "the Gravy Lord"]
const GOLEM := ["Pebbles", "Rocky", "Sir Gravel", "Boulder Dash", "Lord Gravelbottom", "Clod", "Stoney Baloney",
	"Craig", "Gneiss Guy", "Rock Hudson", "Dwayne", "Shale O'Neal", "Chip", "Flint Eastwood", "Brick Tamland",
	"Mossy", "Slab", "Big Lumpy", "Pebbles McGee", "Quartz Quentin", "Cobble Bob", "The Rock (Not That One)",
	"Grumbles", "Sediment Steve", "Rubble Trouble", "Lil' Landslide", "Granite Grandpa", "Marble Marvin",
	"Stomper", "Basalt Barry", "Tuff Stuff", "Kidney Stone", "Mr. Crumbles", "Ore-ville", "Agnes the Rock"]
const TITAN := ["Mount Kevin", "Big Gerald", "The Absolute Unit", "Colossal Carl", "Mountainous Maureen",
	"Sir Stompsalot", "Lord Biggington", "Boulderdad", "The Pebble's Revenge", "Granite Grandmaster",
	"Rockzilla", "Chonk of Ages"]


## A fresh fighter's name: "First the Epithet" (an epithet most of the time).
static func npc(rng_v: int = -1) -> String:
	var r := rng_v if rng_v >= 0 else randi()
	var f: String = FIRST[r % FIRST.size()]
	var e: String = EPITHET[(r / FIRST.size()) % EPITHET.size()]
	return f if (r / 7) % 6 == 0 else "%s %s" % [f, e]


## A golem's name, the same on every screen (picked from its id).
static func golem(id: int, titan: bool) -> String:
	var h: int = absi(hash(id * 7919 + 13))
	return TITAN[h % TITAN.size()] if titan else GOLEM[h % GOLEM.size()]
