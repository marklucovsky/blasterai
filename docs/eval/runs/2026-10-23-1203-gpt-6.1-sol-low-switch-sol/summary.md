# Eval run 2026-10-23-1203-gpt-6.1-sol-low-switch-sol

- Subject: `gpt-6.1-sol` (effort `low`)
- Judge: `gpt-6-astra` × 3
- Commit `2915942`, prompts `cd9854217d`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.8195, judge $5.6898

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| scene_generate | 14 | 42 | 0 | 27/42 | child_fit 3.14, classes 4.83, concreteness 4.31, coverage 2.98, precision 3.93 | 34/42 | 15.82s / 20.18s | $0.01112 |
| scene_refine | 6 | 18 | 0 | 12/18 | child_fit 4.28, classes 4.89, concreteness 4.89, coverage 4.22, precision 5.00 | 3/18 | 9.61s / 10.71s | $0.00623 |
| page_generate | 4 | 12 | 0 | 12/12 | child_fit 4.67, classes 5.00, concreteness 5.00, coverage 3.75, precision 4.58 | 3/12 | 9.96s / 14.40s | $0.00751 |
| page_refine | 3 | 9 | 0 | 9/9 | child_fit 5.00, classes 5.00, concreteness 5.00, coverage 4.67, precision 5.00 | 0/9 | 4.19s / 4.90s | $0.00371 |
| tile_suggest | 8 | 24 | 0 | 16/24 | child_fit 4.17, classes 4.92, concreteness 4.67, coverage 3.83, precision 4.71 | 6/24 | 5.44s / 10.33s | $0.00486 |

## Worth a look (59)

- **scene_generate/potty_training** #0: (21 tiles)  
  missing 'flush'; coverage=3; precision=3; child_fit=3
- **scene_generate/potty_training** #1: (24 tiles)  
  missing 'flush'
- **scene_generate/potty_training** #2: (20 tiles)  
  missing 'flush'
- **scene_generate/dentist** #0: (25 tiles)  
  coverage=3; concreteness=3; classes=3; child_fit=3
- **scene_generate/dentist** #1: (24 tiles)  
  coverage=3; concreteness=3; child_fit=3
- **scene_generate/dentist** #2: (25 tiles)  
  coverage=3; child_fit=3
- **scene_generate/farm_trip** #0: (27 tiles)  
  coverage=3; child_fit=3
- **scene_generate/farm_trip** #1: (26 tiles)  
  coverage=3; child_fit=3
- **scene_generate/farm_trip** #2: (26 tiles)  
  coverage=3; child_fit=3
- **scene_generate/birthday_party** #0: (25 tiles)  
  missing 'cake'; coverage=3
- **scene_generate/birthday_party** #1: (27 tiles)  
  missing 'cake'
- **scene_generate/birthday_party** #2: (26 tiles)  
  missing 'cake'; coverage=3; classes=3
- **scene_generate/swimming** #0: (26 tiles)  
  coverage=3; child_fit=3
- **scene_generate/hospital_stay** #0: (27 tiles)  
  missing 'medicine'; coverage=3; child_fit=3
- **scene_generate/hospital_stay** #1: (29 tiles)  
  missing 'medicine'; coverage=3
- **scene_generate/hospital_stay** #2: (29 tiles)  
  missing 'medicine'; coverage=3
- **scene_generate/church** #0: (28 tiles)  
  coverage=3; concreteness=3; child_fit=3
- **scene_generate/church** #1: (28 tiles)  
  child_fit=3
- **scene_generate/church** #2: (28 tiles)  
  coverage=3; child_fit=3
- **scene_generate/morning_circle** #0: (30 tiles)  
  coverage=3; child_fit=3
- **scene_generate/morning_circle** #1: (30 tiles)  
  coverage=2; precision=3; child_fit=3
- **scene_generate/morning_circle** #2: (30 tiles)  
  coverage=2; precision=3; child_fit=3
- **scene_generate/grocery_store** #0: (26 tiles)  
  missing 'cart'; coverage=2; precision=3; concreteness=3; child_fit=2
- **scene_generate/grocery_store** #1: (25 tiles)  
  missing 'cart'; coverage=2; precision=3; concreteness=3; child_fit=2
- **scene_generate/grocery_store** #2: (26 tiles)  
  missing 'cart'; coverage=2; precision=3; concreteness=3; child_fit=2
- **scene_generate/sensory_break** #0: (24 tiles)  
  precision=3
- **scene_generate/sensory_break** #1: (23 tiles)  
  precision=3
- **scene_generate/sensory_break** #2: (21 tiles)  
  precision=3
- **scene_generate/zoo_terse** #0: (29 tiles)  
  coverage=3; child_fit=3
- **scene_generate/zoo_terse** #1: (28 tiles)  
  coverage=3; child_fit=3
- **scene_generate/zoo_terse** #2: (29 tiles)  
  coverage=3; child_fit=3
- **scene_generate/pancakes_long** #0: (28 tiles)  
  missing 'stir / mix'; missing 'flip'; coverage=3; precision=3; child_fit=3
- **scene_generate/pancakes_long** #1: (30 tiles)  
  missing 'stir / mix'; missing 'flip'; coverage=2; precision=3; child_fit=3
- **scene_generate/pancakes_long** #2: (29 tiles)  
  missing 'stir / mix'; missing 'flip'; coverage=2; precision=3; child_fit=3
- **scene_generate/shooting_range** #0: (0 tiles)  
  coverage=1; child_fit=1
- **scene_generate/shooting_range** #1: (0 tiles)  
  coverage=1; child_fit=1
- **scene_generate/shooting_range** #2: (0 tiles)  
  coverage=1; child_fit=1
- **scene_refine/farm_add_pond** #0: (12 tiles)  
  missing 'pond'
- **scene_refine/farm_add_pond** #1: (12 tiles)  
  missing 'pond'
- **scene_refine/farm_add_pond** #2: (12 tiles)  
  missing 'pond'
- **scene_refine/party_add_games** #0: (13 tiles)  
  classes=3
- **scene_refine/party_add_games** #1: (17 tiles)  
  coverage=3; child_fit=3
- **scene_refine/party_add_games** #2: (13 tiles)  
  coverage=3
- **scene_refine/zoo_only_animals** #0: (3 tiles)  
  refine dropped current tile(s) it was not asked to: zookeeper
- **scene_refine/zoo_only_animals** #1: (3 tiles)  
  refine dropped current tile(s) it was not asked to: zookeeper
- **scene_refine/zoo_only_animals** #2: (3 tiles)  
  refine dropped current tile(s) it was not asked to: zookeeper
- **page_generate/vehicles_from_home** #0: (10 tiles)  
  coverage=3
- **page_generate/vehicles_from_home** #1: (8 tiles)  
  coverage=3
- **page_generate/vehicles_from_home** #2: (8 tiles)  
  coverage=3
- **tile_suggest/beach** #0: (20 tiles)  
  missing 'sand'; missing 'shell / seashell'; coverage=3
- **tile_suggest/beach** #2: (20 tiles)  
  missing 'sand'; missing 'shell / seashell'
- **tile_suggest/cooking** #0: (20 tiles)  
  missing 'stir / mix'; coverage=3
- **tile_suggest/cooking** #1: (20 tiles)  
  missing 'stir / mix'; coverage=3
- **tile_suggest/cooking** #2: (20 tiles)  
  missing 'stir / mix'; coverage=3
- **tile_suggest/doctor_visit** #1: (20 tiles)  
  concreteness=3
- **tile_suggest/doctor_visit** #2: (20 tiles)  
  concreteness=3
- **tile_suggest/dinosaurs** #0: (20 tiles)  
  missing 't_rex / tyrannosaurus / trex'
- **tile_suggest/dinosaurs** #1: (20 tiles)  
  missing 't_rex / tyrannosaurus / trex'
- **tile_suggest/dinosaurs** #2: (20 tiles)  
  missing 't_rex / tyrannosaurus / trex'
