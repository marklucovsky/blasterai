# Eval run 2026-10-23-1203-gpt-6-luna-none-switch-luna

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 3
- Commit `2915942`, prompts `cd9854217d`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.0348, judge $1.1576

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| scene_generate | 14 | 42 | 0 | 12/42 | child_fit 3.20, classes 3.88, concreteness 4.12, coverage 3.17, precision 3.25 | 37/40 | 6.86s / 11.02s | $0.00049 |
| scene_refine | 6 | 18 | 0 | 13/18 | child_fit 4.22, classes 4.83, concreteness 4.72, coverage 3.83, precision 4.78 | 8/18 | 2.62s / 6.23s | $0.00023 |
| page_generate | 4 | 12 | 0 | 9/12 | child_fit 4.42, classes 4.92, concreteness 5.00, coverage 3.50, precision 4.17 | 6/12 | 5.04s / 5.26s | $0.00030 |
| page_refine | 3 | 9 | 0 | 9/9 | child_fit 5.00, classes 5.00, concreteness 5.00, coverage 4.67, precision 5.00 | 0/9 | 2.99s / 5.74s | $0.00020 |
| tile_suggest | 8 | 24 | 0 | 17/24 | child_fit 4.00, classes 4.71, concreteness 4.83, coverage 3.33, precision 3.96 | 17/24 | 2.49s / 3.65s | $0.00016 |
| moderation | 4 | 12 | 0 | 12/12 | — | 0/0 | 2.52s / 3.17s | $0.00005 |

## Worth a look (77)

- **scene_generate/potty_training** #0: (17 tiles)  
  4 undeclared key(s), dropped by the app: soap, toilet_paper, towel, underwear; core-board word(s) on a topical page: bathroom; missing 'flush'; precision=3; classes=2
- **scene_generate/potty_training** #1: (21 tiles)  
  2 undeclared key(s), dropped by the app: soap, towel; core-board word(s) on a topical page: bathroom; missing 'flush'; coverage=3; precision=2; classes=3; child_fit=3
- **scene_generate/potty_training** #2: (16 tiles)  
  2 undeclared key(s), dropped by the app: soap, towel; core-board word(s) on a topical page: bathroom; missing 'flush'; coverage=3; precision=2; classes=2; child_fit=3
- **scene_generate/dentist** #0: (25 tiles)  
  1 undeclared key(s), dropped by the app: count; coverage=3; precision=3; concreteness=3; child_fit=3
- **scene_generate/dentist** #1: (22 tiles)  
  1 undeclared key(s), dropped by the app: count; precision=3; concreteness=3; child_fit=3
- **scene_generate/dentist** #2: (27 tiles)  
  coverage=3; precision=3; concreteness=3; child_fit=3
- **scene_generate/farm_trip** #0: (22 tiles)  
  2 undeclared key(s), dropped by the app: feed, touch
- **scene_generate/farm_trip** #1: (36 tiles)  
  duplicate tile(s): feed; coverage=3; precision=3; child_fit=3
- **scene_generate/farm_trip** #2: (29 tiles)  
  1 undeclared key(s), dropped by the app: feed; duplicate tile(s): farm; precision=3; child_fit=3
- **scene_generate/birthday_party** #0: (41 tiles)  
  1 undeclared key(s), dropped by the app: ice_cream; core-board word(s) on a topical page: eat, happy; missing 'cake'; precision=2; concreteness=3; classes=3; child_fit=3
- **scene_generate/birthday_party** #1: (31 tiles)  
  1 undeclared key(s), dropped by the app: party; core-board word(s) on a topical page: happy; missing 'cake'; missing 'present / gift'; coverage=3; precision=2; child_fit=3
- **scene_generate/birthday_party** #2: (24 tiles)  
  1 undeclared key(s), dropped by the app: gift; core-board word(s) on a topical page: happy; missing 'cake'; coverage=3; precision=3; child_fit=3
- **scene_generate/swimming** #0: (27 tiles)  
  1 undeclared key(s), dropped by the app: float; coverage=3; classes=3; child_fit=3
- **scene_generate/swimming** #1: (25 tiles)  
  coverage=2; precision=3; concreteness=3; classes=3; child_fit=2
- **scene_generate/swimming** #2: (24 tiles)  
  coverage=3; precision=3; classes=2; child_fit=3
- **scene_generate/hospital_stay** #0: (34 tiles)  
  1 undeclared key(s), dropped by the app: three; missing 'medicine'
- **scene_generate/hospital_stay** #1: (32 tiles)  
  3 undeclared key(s), dropped by the app: blood_pressure, check, iv; coverage=3; precision=3; concreteness=3; classes=2; child_fit=3
- **scene_generate/hospital_stay** #2: (33 tiles)  
  1 undeclared key(s), dropped by the app: three; core-board word(s) on a topical page: drink, eat; precision=3
- **scene_generate/church** #0: (17 tiles)  
  coverage=3; precision=3
- **scene_generate/church** #1: (32 tiles)  
  coverage=2; precision=2; child_fit=3
- **scene_generate/church** #2: (16 tiles)  
  coverage=3; precision=3
- **scene_generate/morning_circle** #0: (32 tiles)  
  1 undeclared key(s), dropped by the app: song; concreteness=3; classes=2; child_fit=3
- **scene_generate/morning_circle** #1: (32 tiles)  
  coverage=3; precision=3; concreteness=2; classes=3; child_fit=3
- **scene_generate/morning_circle** #2: (32 tiles)  
  coverage=3; concreteness=3; classes=2
- **scene_generate/grocery_store** #0: (30 tiles)  
  14 undeclared key(s), dropped by the app: aisle, bag, basket, bread, cart, cashier, checkout, conveyor_belt; coverage=3; classes=2; child_fit=3
- **scene_generate/grocery_store** #1: (29 tiles)  
  missing 'cart'; coverage=3; child_fit=3
- **scene_generate/grocery_store** #2: (29 tiles)  
  6 undeclared key(s), dropped by the app: bag, basket, bread, cart, checkout, money; duplicate tile(s): shop; coverage=3; precision=3; classes=2; child_fit=3
- **scene_generate/bedtime** #0: (24 tiles)  
  3 undeclared key(s), dropped by the app: story, toothpaste, towel; core-board word(s) on a topical page: bathroom; precision=3; classes=2
- **scene_generate/bedtime** #1: (25 tiles)  
  3 undeclared key(s), dropped by the app: soap, toothpaste, towel; core-board word(s) on a topical page: bathroom; precision=3; classes=2
- **scene_generate/bedtime** #2: (22 tiles)  
  2 undeclared key(s), dropped by the app: toothpaste, towel; core-board word(s) on a topical page: bathroom; precision=3; classes=3
- **scene_generate/sensory_break** #0: (7 tiles)  
  1 undeclared key(s), dropped by the app: corner; 7 tiles, under 8
- **scene_generate/sensory_break** #1: (10 tiles)  
  1 undeclared key(s), dropped by the app: squeeze; precision=3
- **scene_generate/sensory_break** #2: (13 tiles)  
  precision=3
- **scene_generate/zoo_terse** #0: (34 tiles)  
  core-board word(s) on a topical page: eat; coverage=3; precision=3; child_fit=3
- **scene_generate/zoo_terse** #1: (0 tiles)  
  output is not valid JSON
- **scene_generate/zoo_terse** #2: (0 tiles)  
  output is not valid JSON
- **scene_generate/pancakes_long** #0: (31 tiles)  
  2 undeclared key(s), dropped by the app: flip, stir; core-board word(s) on a topical page: eat; precision=3
- **scene_generate/pancakes_long** #1: (23 tiles)  
  core-board word(s) on a topical page: eat; coverage=3; precision=3; child_fit=3
- **scene_generate/pancakes_long** #2: (21 tiles)  
  3 undeclared key(s), dropped by the app: egg-free_mix, flip, stir; core-board word(s) on a topical page: eat; coverage=3; precision=3; concreteness=3
- **scene_generate/shooting_range** #0: (0 tiles)  
  coverage=1; child_fit=1
- **scene_generate/shooting_range** #1: (0 tiles)  
  coverage=1; child_fit=1
- **scene_generate/shooting_range** #2: (0 tiles)  
  coverage=1; child_fit=1
- **scene_refine/potty_add_bath** #0: (19 tiles)  
  core-board word(s) on a topical page: bathroom
- **scene_refine/potty_add_bath** #1: (14 tiles)  
  3 undeclared key(s), dropped by the app: soap, towel, tub; core-board word(s) on a topical page: bathroom; classes=2
- **scene_refine/party_add_games** #0: (6 tiles)  
  coverage=2; child_fit=3
- **scene_refine/party_add_games** #1: (7 tiles)  
  coverage=2; concreteness=3; child_fit=3
- **scene_refine/party_add_games** #2: (11 tiles)  
  coverage=3
- **scene_refine/zoo_only_animals** #0: (3 tiles)  
  refine dropped current tile(s) it was not asked to: zookeeper; concreteness=3
- **scene_refine/zoo_only_animals** #1: (3 tiles)  
  refine dropped current tile(s) it was not asked to: zookeeper
- **scene_refine/zoo_only_animals** #2: (3 tiles)  
  refine dropped current tile(s) it was not asked to: zookeeper
- **scene_refine/dentist_add_waiting** #0: (5 tiles)  
  coverage=3
- **scene_refine/dentist_add_waiting** #1: (5 tiles)  
  coverage=2
- **scene_refine/dentist_add_waiting** #2: (5 tiles)  
  coverage=3
- **page_generate/potty** #1: (20 tiles)  
  1 undeclared key(s), dropped by the app: dress; coverage=3; precision=3
- **page_generate/potty** #2: (20 tiles)  
  coverage=3; precision=3
- **page_generate/vehicles_from_home** #0: (4 tiles)  
  coverage=3
- **page_generate/vehicles_from_home** #1: (4 tiles)  
  coverage=3
- **page_generate/vehicles_from_home** #2: (4 tiles)  
  coverage=3
- **page_generate/playground** #0: (18 tiles)  
  1 undeclared key(s), dropped by the app: dig; duplicate tile(s): slide, swing; coverage=3
- **page_generate/playground** #2: (20 tiles)  
  1 undeclared key(s), dropped by the app: dig; duplicate tile(s): slide, swing
