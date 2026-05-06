```markdown
# step1_project_init.md

## Technical Specification: Project Initialization & Data Architecture
**Target Engine:** Godot 4.x  
**Execution Agent:** Cursor (AI Coder)  
**Step:** 1 of 10 — No GDScript logic. Folder scaffolding and JSON seeding ONLY.

---

## DIRECTIVE CONSTRAINTS (READ BEFORE EXECUTING)

- **DO NOT** write any `.gd` files in this step.
- **DO NOT** write any `.tscn` or `.tres` files in this step.
- **DO NOT** write any logic, functions, or variables.
- **ONLY** create the folder hierarchy and the three JSON data files specified below.
- All JSON must be valid. Run a mental lint pass before outputting. No trailing commas.
- Confirm completion with a checklist. Do not proceed to Step 2 until confirmed.

---

## SECTION 1: REQUIRED FOLDER HIERARCHY

Create the following directory tree under the Godot project root (`res://`). Create a `.gitkeep` placeholder file inside each leaf folder to ensure Git tracks empty directories.

```
res://
├── assets/
│   ├── fonts/
│   │   └── .gitkeep
│   ├── sfx/
│   │   └── .gitkeep
│   ├── music/
│   │   └── .gitkeep
│   └── sprites/
│       ├── ui/
│       │   └── .gitkeep
│       ├── slots/
│       │   └── .gitkeep
│       ├── villages/
│       │   └── .gitkeep
│       └── pets/
│           └── .gitkeep
├── src/
│   ├── core/
│   │   └── .gitkeep
│   ├── ui/
│   │   └── .gitkeep
│   ├── data/
│   │   └── .gitkeep
│   ├── utils/
│   │   └── .gitkeep
│   └── events/
│       └── .gitkeep
└── docs/
    └── .gitkeep
```

### Folder Responsibility Contract (for AI context in future steps)

| Folder | Strict Purpose | What NEVER belongs here |
|---|---|---|
| `src/core/` | Pure math/logic scripts: SlotMachineLogic, VillageManager, PetManager, CardManager. No Node dependencies. | UI nodes, signals to visual elements, Input handling |
| `src/ui/` | View-only scripts: HUD, Menus, Modals, Animations. Emits signals upward. Reads state passively. | Game math, RNG calls, direct resource mutation |
| `src/data/` | Static JSON config files only. Read-only at runtime. | Any generated or mutable save data |
| `src/utils/` | Cross-cutting infrastructure: SaveLoadManager, Logger, TimeSync. Autoload Singletons only. | Game-specific domain logic |
| `src/events/` | Live-ops event classes inheriting BaseEvent. Self-contained event state machines. | Core slot logic, village cost calculations |
| `assets/` | Binary assets only: PNG, WAV, OGG, TTF. | Any `.gd`, `.json`, `.tscn` files |
| `docs/` | Markdown specs, `.cursorrules`, per-system context files. | Source code of any kind |

---

## SECTION 2: JSON FILE SPECIFICATIONS

### FILE 1: `res://src/data/village_costs.json`

**Purpose:** Defines the upgrade cost in Coins for every item level across the first 10 villages. Used exclusively by `VillageManager.gd`. No other system reads this file.

**Schema Contract:**
- Top-level key: `"villages"` → Array of village objects.
- Each village object:
  - `"id"`: Integer (1-indexed).
  - `"name"`: String (thematic name).
  - `"items"`: Array of exactly **5** item objects.
- Each item object:
  - `"item_index"`: Integer 0–4.
  - `"label"`: String (descriptive name for UI).
  - `"upgrade_costs"`: Array of exactly **5** integers representing cost for levels 1→2, 2→3, 3→4, 4→5, and 5→Complete.

**Scaling Formula Applied:**  
Base cost for village `v`, item `i`, level `l`:  
`cost = floor(base_village_cost * item_weight[i] * level_multiplier[l])`  
where `base_village_cost` scales exponentially (~1.6x per village), `item_weight` distributes cost unevenly across items (0.15, 0.18, 0.22, 0.20, 0.25), and `level_multiplier` is `[0.10, 0.15, 0.20, 0.25, 0.30]`.

**Output this exact JSON:**

```json
{
  "villages": [
    {
      "id": 1,
      "name": "Lands of Vikings",
      "items": [
        { "item_index": 0, "label": "Longhouse", "upgrade_costs": [155000, 232500, 310000, 387500, 465000] },
        { "item_index": 1, "label": "Forge", "upgrade_costs": [186000, 279000, 372000, 465000, 558000] },
        { "item_index": 2, "label": "Great Hall", "upgrade_costs": [232000, 348000, 464000, 580000, 696000] },
        { "item_index": 3, "label": "Docks", "upgrade_costs": [210000, 315000, 420000, 525000, 630000] },
        { "item_index": 4, "label": "Runestone", "upgrade_costs": [263000, 394500, 526000, 657500, 789000] }
      ]
    },
    {
      "id": 2,
      "name": "Ancient Egypt",
      "items": [
        { "item_index": 0, "label": "Pyramid", "upgrade_costs": [248000, 372000, 496000, 620000, 744000] },
        { "item_index": 1, "label": "Sphinx", "upgrade_costs": [297600, 446400, 595200, 744000, 892800] },
        { "item_index": 2, "label": "Obelisk", "upgrade_costs": [371200, 556800, 742400, 928000, 1113600] },
        { "item_index": 3, "label": "Bazaar", "upgrade_costs": [336000, 504000, 672000, 840000, 1008000] },
        { "item_index": 4, "label": "Tomb", "upgrade_costs": [420800, 631200, 841600, 1052000, 1262400] }
      ]
    },
    {
      "id": 3,
      "name": "Snowy Alps",
      "items": [
        { "item_index": 0, "label": "Chalet", "upgrade_costs": [396800, 595200, 793600, 992000, 1190400] },
        { "item_index": 1, "label": "Cable Car", "upgrade_costs": [476160, 714240, 952320, 1190400, 1428480] },
        { "item_index": 2, "label": "Ski Lodge", "upgrade_costs": [593920, 890880, 1187840, 1484800, 1781760] },
        { "item_index": 3, "label": "Ice Rink", "upgrade_costs": [537600, 806400, 1075200, 1344000, 1612800] },
        { "item_index": 4, "label": "Monastery", "upgrade_costs": [673280, 1009920, 1346560, 1683200, 2019840] }
      ]
    },
    {
      "id": 4,
      "name": "Inca",
      "items": [
        { "item_index": 0, "label": "Temple", "upgrade_costs": [634880, 952320, 1269760, 1587200, 1904640] },
        { "item_index": 1, "label": "Terrace Farm", "upgrade_costs": [761856, 1142784, 1523712, 1904640, 2285568] },
        { "item_index": 2, "label": "Sun Gate", "upgrade_costs": [950272, 1425408, 1900544, 2375680, 2850816] },
        { "item_index": 3, "label": "Citadel", "upgrade_costs": [860160, 1290240, 1720320, 2150400, 2580480] },
        { "item_index": 4, "label": "Gold Vault", "upgrade_costs": [1077248, 1615872, 2154496, 2693120, 3231744] }
      ]
    },
    {
      "id": 5,
      "name": "Far East",
      "items": [
        { "item_index": 0, "label": "Pagoda", "upgrade_costs": [1015808, 1523712, 2031616, 2539520, 3047424] },
        { "item_index": 1, "label": "Dojo", "upgrade_costs": [1218969, 1828453, 2437938, 3047422, 3656906] },
        { "item_index": 2, "label": "Torii Gate", "upgrade_costs": [1520435, 2280652, 3040870, 3801088, 4561305] },
        { "item_index": 3, "label": "Tea House", "upgrade_costs": [1376256, 2064384, 2752512, 3440640, 4128768] },
        { "item_index": 4, "label": "Bamboo Forest", "upgrade_costs": [1723596, 2585394, 3447193, 4308992, 5170790] }
      ]
    },
    {
      "id": 6,
      "name": "Atlantis",
      "items": [
        { "item_index": 0, "label": "Crystal Spire", "upgrade_costs": [1625292, 2437939, 3250586, 4063232, 4875878] },
        { "item_index": 1, "label": "Aqua Dome", "upgrade_costs": [1950350, 2925525, 3900701, 4875876, 5851051] },
        { "item_index": 2, "label": "Trident Monument", "upgrade_costs": [2432696, 3649044, 4865393, 6081741, 7298089] },
        { "item_index": 3, "label": "Pearl Market", "upgrade_costs": [2201610, 3302415, 4403220, 5504025, 6604830] },
        { "item_index": 4, "label": "Sunken Library", "upgrade_costs": [2757754, 4136630, 5515507, 6894384, 8273260] }
      ]
    },
    {
      "id": 7,
      "name": "Wild West",
      "items": [
        { "item_index": 0, "label": "Saloon", "upgrade_costs": [2600467, 3900701, 5200934, 6501168, 7801402] },
        { "item_index": 1, "label": "Sheriff Office", "upgrade_costs": [3120560, 4680840, 6241121, 7801401, 9361681] },
        { "item_index": 2, "label": "Gold Mine", "upgrade_costs": [3893213, 5839819, 7786426, 9733032, 11679638] },
        { "item_index": 3, "label": "Train Station", "upgrade_costs": [3522576, 5283864, 7045152, 8806440, 10567728] },
        { "item_index": 4, "label": "Frontier Fort", "upgrade_costs": [4412406, 6618609, 8824812, 11031015, 13237218] }
      ]
    },
    {
      "id": 8,
      "name": "Medieval Kingdom",
      "items": [
        { "item_index": 0, "label": "Castle Keep", "upgrade_costs": [4160747, 6241121, 8321494, 10401868, 12482241] },
        { "item_index": 1, "label": "Jousting Arena", "upgrade_costs": [4992897, 7489345, 9985793, 12482241, 14978689] },
        { "item_index": 2, "label": "Cathedral", "upgrade_costs": [6231341, 9347011, 12462682, 15578352, 18694022] },
        { "item_index": 3, "label": "Blacksmith", "upgrade_costs": [5636121, 8454182, 11272242, 14090303, 16908363] },
        { "item_index": 4, "label": "Royal Treasury", "upgrade_costs": [7059850, 10589775, 14119700, 17649625, 21179550] }
      ]
    },
    {
      "id": 9,
      "name": "Space Station",
      "items": [
        { "item_index": 0, "label": "Launch Pad", "upgrade_costs": [6657195, 9985793, 13314390, 16642988, 19971585] },
        { "item_index": 1, "label": "Observatory", "upgrade_costs": [7988634, 11982951, 15977268, 19971585, 23965902] },
        { "item_index": 2, "label": "Reactor Core", "upgrade_costs": [9970145, 14955217, 19940290, 24925362, 29910434] },
        { "item_index": 3, "label": "Cryo Chamber", "upgrade_costs": [9017793, 13526690, 18035586, 22544483, 27053379] },
        { "item_index": 4, "label": "Command Bridge", "upgrade_costs": [11295761, 16943641, 22591522, 28239402, 33887282] }
      ]
    },
    {
      "id": 10,
      "name": "Atlantis Reborn",
      "items": [
        { "item_index": 0, "label": "Titan Colossus", "upgrade_costs": [10651512, 15977268, 21303024, 26628780, 31954536] },
        { "item_index": 1, "label": "Nebula Forge", "upgrade_costs": [12781814, 19172722, 25563629, 31954536, 38345443] },
        { "item_index": 2, "label": "Void Gate", "upgrade_costs": [15952232, 23928349, 31904465, 39880581, 47856697] },
        { "item_index": 3, "label": "Echo Market", "upgrade_costs": [14428469, 21642704, 28856938, 36071173, 43285407] },
        { "item_index": 4, "label": "Genesis Vault", "upgrade_costs": [18073050, 27109575, 36146100, 45182625, 54219150] }
      ]
    }
  ]
}
```

---

### FILE 2: `res://src/data/slot_weights.json`

**Purpose:** Defines the weighted probability matrix for all slot machine outcomes. Read exclusively by `SlotMachineLogic.gd`. The `weight` field is a relative integer. Probability = `weight / sum_of_all_weights`.

**Schema Contract:**
- Top-level key: `"outcomes"` → Array of outcome objects.
- Each outcome object:
  - `"id"`: String — machine-readable unique identifier. Used as the return value key.
  - `"label"`: String — human-readable display name for UI and debugging.
  - `"weight"`: Integer — relative probability weight. Higher = more frequent.
  - `"reward_type"`: String — enum of `"coins"`, `"spins"`, `"shield"`, `"attack"`, `"raid"`. Tells the logic layer what resource to mutate.
  - `"reward_value"`: Integer — base resource amount awarded. Multiplied by `bet_multiplier` at runtime for coins. Spins/Shield/Attack/Raid are fixed counts.
  - `"reward_tier"`: String — enum of `"small"`, `"medium"`, `"large"`, `"jackpot"`. Used by UI layer to trigger appropriate animation intensity.
  - `"three_of_a_kind_only"`: Boolean — if `true`, this outcome only activates when all 3 reels match. If `false`, a single symbol appearance triggers the reward.
  - `"max_held"`: Integer or `null` — maximum stack the player can hold of this reward type. `null` means unlimited (coins). Used by the cap-check logic.

**Weight Distribution Rationale:** Coins dominate (~65% combined) to maintain resource flow. Spins are scarce (~10%) to create tension. Shields, Attacks, Raids are meaningful but infrequent (~8% each) to preserve strategic value.

```json
{
  "outcomes": [
    {
      "id": "coins_small",
      "label": "Coin",
      "weight": 340,
      "reward_type": "coins",
      "reward_value": 50,
      "reward_tier": "small",
      "three_of_a_kind_only": false,
      "max_held": null
    },
    {
      "id": "coins_medium",
      "label": "Coin Bag",
      "weight": 210,
      "reward_type": "coins",
      "reward_value": 200,
      "reward_tier": "medium",
      "three_of_a_kind_only": false,
      "max_held": null
    },
    {
      "id": "coins_large",
      "label": "Coin Chest",
      "weight": 95,
      "reward_type": "coins",
      "reward_value": 800,
      "reward_tier": "large",
      "three_of_a_kind_only": true,
      "max_held": null
    },
    {
      "id": "coins_jackpot",
      "label": "Coin Hoard",
      "weight": 12,
      "reward_type": "coins",
      "reward_value": 5000,
      "reward_tier": "jackpot",
      "three_of_a_kind_only": true,
      "max_held": null
    },
    {
      "id": "spins_single",
      "label": "Energy Capsule",
      "weight": 75,
      "reward_type": "spins",
      "reward_value": 1,
      "reward_tier": "small",
      "three_of_a_kind_only": false,
      "max_held": null
    },
    {
      "id": "spins_bonus",
      "label": "Energy Crate",
      "weight": 28,
      "reward_type": "spins",
      "reward_value": 5,
      "reward_tier": "medium",
      "three_of_a_kind_only": true,
      "max_held": null
    },
    {
      "id": "shield_single",
      "label": "Shield",
      "weight": 88,
      "reward_type": "shield",
      "reward_value": 1,
      "reward_tier": "small",
      "three_of_a_kind_only": false,
      "max_held": 5
    },
    {
      "id": "attack_single",
      "label": "Hammer",
      "weight": 72,
      "reward_type": "attack",
      "reward_value": 1,
      "reward_tier": "small",
      "three_of_a_kind_only": false,
      "max_held": null
    },
    {
      "id": "attack_triple",
      "label": "Wrecking Ball",
      "weight": 18,
      "reward_type": "attack",
      "reward_value": 3,
      "reward_tier": "large",
      "three_of_a_kind_only": true,
      "max_held": null
    },
    {
      "id": "raid_single",
      "label": "Pig Bandit",
      "weight": 55,
      "reward_type": "raid",
      "reward_value": 1,
      "reward_tier": "small",
      "three_of_a_kind_only": false,
      "max_held": null
    },
    {
      "id": "raid_triple",
      "label": "Pirate Fleet",
      "weight": 7,
      "reward_type": "raid",
      "reward_value": 3,
      "reward_tier": "jackpot",
      "three_of_a_kind_only": true,
      "max_held": null
    }
  ],
  "_meta": {
    "total_weight_sum": 1000,
    "note": "total_weight_sum is informational only. SlotMachineLogic.gd MUST compute the real sum dynamically at runtime from the array. Do not hardcode 1000 in logic.",
    "shield_overflow_behavior": "If shield outcome is selected but player.shields >= max_held, intercept: refund the spin cost and award coins_small.reward_value instead.",
    "rng_override_key": "forced_outcome_id",
    "rng_override_note": "If SaveLoadManager contains a non-null forced_outcome_id key, SlotMachineLogic bypasses weighted selection and returns that outcome directly. TrainerConsole writes this key. Logic layer clears it after one use."
  }
}
```

---

### FILE 3: `res://src/data/shop_items.json`

**Purpose:** Defines all simulated IAP product listings for the in-game storefront. Read exclusively by the shop UI layer. In offline/desktop builds, selecting an item injects currency directly. No real payment processing occurs.

**Schema Contract:**
- Top-level key: `"products"` → Array of product objects.
- Each product object:
  - `"id"`: String — unique SKU. Matches platform store product IDs when real IAP is later integrated.
  - `"display_name"`: String — storefront title.
  - `"description"`: String — short marketing copy.
  - `"category"`: String — enum of `"spins_bundle"`, `"coins_bundle"`, `"mixed_bundle"`, `"starter_pack"`, `"vip_pass"`.
  - `"price_usd"`: Float — display price. Cosmetic only in offline mode.
  - `"currency_tag"`: String — e.g. `"$"`, `"€"`. Localisation hook.
  - `"rewards"`: Object — maps reward type keys to integer values. Keys must match `reward_type` enum from `slot_weights.json` plus `"gems"`.
  - `"badge"`: String or `null` — promotional badge text, e.g. `"BEST VALUE"`, `"LIMITED"`, `null`.
  - `"is_one_time_offer"`: Boolean — if `true`, UI greys out after first purchase (tracked in save state).
  - `"sort_order"`: Integer — ascending display order in storefront grid.

```json
{
  "products": [
    {
      "id": "starter_pack_001",
      "display_name": "Starter Bundle",
      "description": "The perfect launchpad for new villages.",
      "category": "starter_pack",
      "price_usd": 1.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 45,
        "coins": 500000,
        "gems": 5
      },
      "badge": "NEW PLAYER",
      "is_one_time_offer": true,
      "sort_order": 1
    },
    {
      "id": "spins_tiny_001",
      "display_name": "Handful of Spins",
      "description": "A small top-up to keep the reels turning.",
      "category": "spins_bundle",
      "price_usd": 1.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 30,
        "coins": 0,
        "gems": 0
      },
      "badge": null,
      "is_one_time_offer": false,
      "sort_order": 2
    },
    {
      "id": "spins_small_001",
      "display_name": "Spin Pouch",
      "description": "Enough spins for a solid session.",
      "category": "spins_bundle",
      "price_usd": 4.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 80,
        "coins": 0,
        "gems": 2
      },
      "badge": null,
      "is_one_time_offer": false,
      "sort_order": 3
    },
    {
      "id": "spins_medium_001",
      "display_name": "Spin Sack",
      "description": "Power through multiple villages.",
      "category": "spins_bundle",
      "price_usd": 9.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 200,
        "coins": 1000000,
        "gems": 5
      },
      "badge": "POPULAR",
      "is_one_time_offer": false,
      "sort_order": 4
    },
    {
      "id": "spins_large_001",
      "display_name": "Spin Barrel",
      "description": "A serious investment for serious builders.",
      "category": "spins_bundle",
      "price_usd": 19.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 500,
        "coins": 5000000,
        "gems": 15
      },
      "badge": "BEST VALUE",
      "is_one_time_offer": false,
      "sort_order": 5
    },
    {
      "id": "spins_xl_001",
      "display_name": "Mega Spin Chest",
      "description": "Dominate the leaderboard for days.",
      "category": "spins_bundle",
      "price_usd": 49.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 1500,
        "coins": 20000000,
        "gems": 50
      },
      "badge": "WHALE TIER",
      "is_one_time_offer": false,
      "sort_order": 6
    },
    {
      "id": "coins_small_001",
      "display_name": "Coin Purse",
      "description": "Finish off that last village upgrade.",
      "category": "coins_bundle",
      "price_usd": 2.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 0,
        "coins": 3000000,
        "gems": 0
      },
      "badge": null,
      "is_one_time_offer": false,
      "sort_order": 7
    },
    {
      "id": "coins_medium_001",
      "display_name": "Coin Vault",
      "description": "Complete two villages in one go.",
      "category": "coins_bundle",
      "price_usd": 9.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 10,
        "coins": 15000000,
        "gems": 3
      },
      "badge": null,
      "is_one_time_offer": false,
      "sort_order": 8
    },
    {
      "id": "mixed_bundle_001",
      "display_name": "Village Builder Pack",
      "description": "Balanced resources to break through any wall.",
      "category": "mixed_bundle",
      "price_usd": 14.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 150,
        "coins": 10000000,
        "gems": 10
      },
      "badge": "LIMITED",
      "is_one_time_offer": false,
      "sort_order": 9
    },
    {
      "id": "vip_pass_001",
      "display_name": "Golden Pass — Season",
      "description": "30-day pass: daily spin bonus, doubled event rewards, exclusive card chest every 3 days.",
      "category": "vip_pass",
      "price_usd": 9.99,
      "currency_tag": "$",
      "rewards": {
        "spins": 50,
        "coins": 2000000,
        "gems": 20
      },
      "badge": "SEASON PASS",
      "is_one_time_offer": false,
      "sort_order": 10
    }
  ],
  "_meta": {
    "note": "price_usd and currency_tag are display-only in offline/desktop/web builds. The shop UI reads these fields for rendering only. On purchase confirmation in offline mode, inject rewards directly into SaveLoadManager state. No payment gateway is called. In future mobile builds, replace the purchase handler with Google Play Billing or Apple StoreKit using the same product id strings.",
    "one_time_offer_save_key": "purchased_one_time_offers",
    "one_time_offer_save_note": "SaveLoadManager must store an Array of purchased one-time offer id strings. Shop UI checks this array before rendering the buy button."
  }
}
```

---

## SECTION 3: COMPLETION CHECKLIST

Before marking Step 1 as complete, Cursor must confirm ALL of the following:

- [ ] `res://src/core/` directory exists with `.gitkeep`
- [ ] `res://src/ui/` directory exists with `.gitkeep`
- [ ] `res://src/data/` directory exists with `.gitkeep`
- [ ] `res://src/utils/` directory exists with `.gitkeep`
- [ ] `res://src/events/` directory exists with `.gitkeep`
- [ ] `res://assets/fonts/`, `res://assets/sfx/`, `res://assets/music/` exist
- [ ] `res://assets/sprites/ui/`, `sprites/slots/`, `sprites/villages/`, `sprites/pets/` exist
- [ ] `res://docs/` directory exists
- [ ] `res://src/data/village_costs.json` is valid JSON, contains exactly 10 village objects, each with exactly 5 items, each item with exactly 5 upgrade cost integers
- [ ] `res://src/data/slot_weights.json` is valid JSON, contains exactly 11 outcome objects, each with all 7 required fields
- [ ] `res://src/data/shop_items.json` is valid JSON, contains exactly 10 product objects, each with all 9 required fields
- [ ] **Zero `.gd` files have been created**
- [ ] **Zero `.tscn` files have been created**
- [ ] All JSON passes a syntax validation check (no trailing commas, no undefined values)

**DO NOT proceed to Step 2 until this checklist is fully checked.**

---

## SECTION 4: NEXT STEP PRIMER (DO NOT EXECUTE YET)

Step 2 will build `res://src/utils/SaveLoadManager.gd` as a Godot Autoload Singleton. It will depend on the JSON structure defined in this document. The `player_state` Dictionary schema it implements will be derived directly from the field names established in `village_costs.json` and `slot_weights.json`. No values from those files may be hardcoded into the GDScript.
```