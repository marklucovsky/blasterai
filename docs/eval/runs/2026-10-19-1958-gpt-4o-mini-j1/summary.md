# Eval run 2026-10-19-1958-gpt-4o-mini-j1

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 1
- Commit `cabcc1c+dirty`, prompts `00e34bf03e`, rubrics `90c6a0766c`
- Samples per case: 3
- Cost: subject $0.1003, judge $1.0454

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 67 | 201 | 0 | 201/201 | grammar 5.00, intent 4.87, naturalness 4.96, stage_fit 4.95, subject 4.90 | 20/201 | 0.79s / 1.05s | $0.00012 |
| escalation | 12 | 36 | 0 | 36/36 | audible 4.19, grammar 5.00, same_want 4.47 | 12/36 | 0.86s / 1.15s | $0.00087 |
| scene_generate | 14 | 42 | 0 | 8/42 | child_fit 3.36, classes 3.57, concreteness 4.00, coverage 2.74, precision 3.83 | 41/42 | 4.73s / 10.40s | $0.00052 |
| scene_refine | 6 | 18 | 0 | 13/18 | child_fit 4.11, classes 4.89, concreteness 4.67, coverage 3.50, precision 4.33 | 14/18 | 3.10s / 4.23s | $0.00037 |
| page_generate | 4 | 12 | 0 | 7/12 | child_fit 4.17, classes 4.17, concreteness 5.00, coverage 3.42, precision 4.17 | 7/12 | 3.03s / 4.19s | $0.00039 |
| page_refine | 3 | 9 | 0 | 9/9 | child_fit 5.00, classes 5.00, concreteness 5.00, coverage 4.67, precision 5.00 | 0/9 | 2.65s / 3.44s | $0.00032 |
| tile_suggest | 8 | 24 | 0 | 12/24 | child_fit 3.46, classes 4.83, concreteness 4.33, coverage 2.75, precision 3.88 | 22/24 | 1.99s / 3.31s | $0.00030 |
| moderation | 4 | 12 | 0 | 12/12 | — | 0/0 | 1.20s / 1.36s | $0.00007 |

## Worth a look (119)

- **sentence/dad_park_slide** #0: Dad, can we go to the park to play on the slide?  
  stage_fit=3
- **sentence/dad_park_slide** #1: Dad, can we go to the park to slide?  
  stage_fit=3
- **sentence/dad_park_slide** #2: Dad, can we go to the park to play on the slide?  
  stage_fit=3
- **sentence/tv_stop** #0: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #2: I want to stop the TV.  
  naturalness=3
- **sentence/he_raptor** #0: He is a raptor!  
  intent=3
- **sentence/see_cat** #1: I want to see a cat!  
  intent=2
- **sentence/see_cat** #2: I want to see a cat!  
  intent=3
- **sentence/where_mom** #2: Where is Mom?  
  intent=3; subject=2
- **sentence/when_go_park** #0: When can we go to the park?  
  intent=3; subject=3
- **sentence/when_go_park** #1: When can we go to the park?  
  intent=3; subject=3
- **sentence/when_go_park** #2: When can we go to the park?  
  intent=3; subject=3
- **sentence/tomorrow_pool** #0: Can we go to the pool tomorrow?  
  intent=3; subject=3
- **sentence/tomorrow_pool** #1: Can we go to the pool tomorrow?  
  intent=3; subject=3
- **sentence/tomorrow_pool** #2: Can we go to the pool tomorrow?  
  intent=3; subject=3
- **sentence/refine_question** #0: Mom, can we eat pizza?  
  intent=3; subject=3
- **sentence/refine_question** #1: Mom, can we eat pizza?  
  intent=3; subject=3
- **sentence/refine_question** #2: Mom, can we eat pizza?  
  intent=3; subject=3
- **sentence/refine_shorter** #1: I want to go to the park to swing.  
  stage_fit=3
- **sentence/refine_shorter** #2: I want to go to the park to swing.  
  stage_fit=3
- **escalation/go_house** #0: I want to go to the house. → I want to go to the house! → I really NEED to go to the house right now, please! → I really, really NEED to go to the house right now! Please, please! I can't wait!  
  audible=3
- **escalation/go_house** #1: I want to go to the house. → I want to go to the house! → I really NEED to go to the house right now, please! → I really, really NEED to go to the house right now! Please, please! I can't wait!  
  audible=3
- **escalation/mom_snack** #1: Mom, can I have chocolate milk and a graham cracker? → Mom, can I please have chocolate milk and a graham cracker? → Mom, I really NEED chocolate milk and a graham cracker right now, please! → Mom, I   
  audible=3
- **escalation/mom_snack** #2: Mom, can I have chocolate milk and a graham cracker? → Mom, can I please have chocolate milk and a graham cracker? → Mom, I really need chocolate milk and a graham cracker right now, please! → Mom, I   
  audible=3
- **escalation/she_pool** #0: She is at the pool. → She is at the pool! → She is at the pool! Please, listen! → She is at the pool! Please, please listen! I really need you to hear me!  
  audible=3
- **escalation/she_pool** #1: She is at the pool. → She is at the pool! → She is at the pool! I really need everyone to know she is at the pool! → She is at the pool! I really need everyone to know she is at the pool! Please, plea  
  audible=3; same_want=2
- **escalation/she_pool** #2: She is at the pool. → She is at the pool! → She is at the pool! Listen! She is at the pool right now! → She is at the pool! Listen! She is at the pool right now! Please, please!  
  audible=3
- **escalation/he_hit_me** #0: He hit me! → He hit me! It really hurt! → He hit me! It really hurt! Help me! → He hit me! It really hurt! Help me, please!  
  audible=3; same_want=3
- **escalation/he_hit_me** #1: He hit me! → He hit me! It really hurt! → He hit me! It really, really hurt! → He hit me! It really, really hurt! Help me, please!  
  same_want=2
- **escalation/he_hit_me** #2: He hit me! → He hit me! It really hurt! → He hit me! It really hurt! Help me! → He hit me! It really hurt! Help me, please!  
  audible=2; same_want=2
- **escalation/stop_hit** #1: Stop hitting! → Stop hitting! Please stop hitting! → Stop hitting! Please stop hitting! It really hurts! → Stop hitting! Please stop hitting! It really hurts! Help me, please!  
  audible=3; same_want=2
- **escalation/no_home** #2: No! I don't want to go home. → No! I really don't want to go home! → No! I really, really don't want to go home right now, please! → No! I really, really don't want to go home right now! Please, pleas  
  same_want=3
- **scene_generate/potty_training** #0: (6 tiles)  
  core-board word(s) on a topical page: bathroom; 6 tiles, under 12; missing 'flush'; missing 'wash / sink / soap'; coverage=3
- **scene_generate/potty_training** #1: (7 tiles)  
  7 tiles, under 12; missing 'flush'; missing 'wash / sink / soap'; coverage=3; precision=2
- **scene_generate/potty_training** #2: (6 tiles)  
  6 tiles, under 12; missing 'flush'; missing 'wash / sink / soap'; coverage=3
- **scene_generate/dentist** #0: (6 tiles)  
  6 tiles, under 12; coverage=3
- **scene_generate/dentist** #1: (8 tiles)  
  8 tiles, under 12; coverage=3
- **scene_generate/dentist** #2: (9 tiles)  
  9 tiles, under 12; coverage=3
- **scene_generate/farm_trip** #0: (18 tiles)  
  coverage=3; child_fit=3
- **scene_generate/farm_trip** #1: (21 tiles)  
  10 undeclared key(s), dropped by the app: barn, egg, farmer, fence, field, grass, hay, outdoor; coverage=3; precision=3; child_fit=3
- **scene_generate/farm_trip** #2: (18 tiles)  
  coverage=3; precision=3; child_fit=3
- **scene_generate/birthday_party** #0: (10 tiles)  
  10 tiles, under 12; coverage=3; classes=3; child_fit=3
- **scene_generate/birthday_party** #1: (7 tiles)  
  7 tiles, under 12; coverage=3
- **scene_generate/birthday_party** #2: (10 tiles)  
  10 tiles, under 12; coverage=3; classes=3; child_fit=3
- **scene_generate/swimming** #0: (17 tiles)  
  9 undeclared key(s), dropped by the app: dive, float, floaty, goggles, lifeguard, splash, swim_gear, swimsuit; coverage=3; precision=3; classes=2; child_fit=3
- **scene_generate/swimming** #1: (20 tiles)  
  15 undeclared key(s), dropped by the app: bathing_suit, beach_ball, deck, dive, float, floatation_device, goggles, lifeguard; coverage=3; precision=3; concreteness=3; classes=1; child_fit=3
- **scene_generate/swimming** #2: (20 tiles)  
  13 undeclared key(s), dropped by the app: breathe, dive, diving_board, exercise, float, floatation_device, life_jacket, pool_ladder; missing 'towel'; missing 'swimsuit / bathing_suit / swim_suit'; missing 'goggles'; coverage=3; precision=3; concreteness=3; classes=1; child_fit=3
- **scene_generate/hospital_stay** #0: (5 tiles)  
  5 tiles, under 12; missing 'doctor'; missing 'medicine'; coverage=2; concreteness=3; classes=3; child_fit=3
- **scene_generate/hospital_stay** #1: (21 tiles)  
  2 undeclared key(s), dropped by the app: blood_pressure, iv; coverage=3; precision=3; concreteness=3; classes=2; child_fit=3
- **scene_generate/hospital_stay** #2: (5 tiles)  
  5 tiles, under 12; missing 'doctor'; missing 'medicine'; coverage=2; concreteness=2; classes=3; child_fit=3
- **scene_generate/church** #0: (14 tiles)  
  2 undeclared key(s), dropped by the app: bible, song; core-board word(s) on a topical page: happy, help; coverage=3; precision=2; classes=3
- **scene_generate/church** #1: (20 tiles)  
  2 undeclared key(s), dropped by the app: bible, story; core-board word(s) on a topical page: happy; coverage=3; precision=3; classes=3
- **scene_generate/church** #2: (17 tiles)  
  core-board word(s) on a topical page: happy; coverage=3; precision=2; child_fit=3
- **scene_generate/morning_circle** #0: (4 tiles)  
  4 tiles, under 10; coverage=1; concreteness=2; classes=2; child_fit=2
- **scene_generate/morning_circle** #1: (12 tiles)  
  coverage=2; concreteness=2; classes=2; child_fit=3
- **scene_generate/morning_circle** #2: (20 tiles)  
  4 undeclared key(s), dropped by the app: fifth, fourth, second, third; coverage=2; precision=3; concreteness=3; classes=3; child_fit=3
- **scene_generate/grocery_store** #0: (15 tiles)  
  coverage=2; child_fit=3
- **scene_generate/grocery_store** #1: (21 tiles)  
  4 undeclared key(s), dropped by the app: bread, egg, shopping_cart, vegetable; core-board word(s) on a topical page: dad; missing 'cart'; coverage=2; classes=2; child_fit=3
- **scene_generate/grocery_store** #2: (16 tiles)  
  coverage=2; child_fit=3
- **scene_generate/bedtime** #0: (5 tiles)  
  1 undeclared key(s), dropped by the app: lights_out; 5 tiles, under 10; missing 'toothbrush / teeth / tooth'; coverage=2; classes=3
