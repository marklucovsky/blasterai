# Eval run 2026-10-19-1522-gpt-4o-mini-v0

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 1
- Commit `8f81084+dirty`, prompts `6d26021a57`, rubrics `c9bea179dc`
- Samples per case: 1
- Cost: subject $0.0331, judge $0.3270

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 67 | 67 | 0 | 56/67 | grammar 4.55, intent 3.12, naturalness 4.19, stage_fit 3.52, subject 3.87 | 50/67 | 0.79s / 1.29s | $0.00014 |
| escalation | 9 | 9 | 0 | 5/9 | audible 2.33, grammar 4.44, same_want 4.56 | 9/9 | 0.84s / 1.02s | $0.00063 |
| scene_generate | 14 | 14 | 0 | 2/14 | child_fit 3.50, classes 3.71, concreteness 4.07, coverage 2.79, precision 3.71 | 14/14 | 5.10s / 8.15s | $0.00061 |
| scene_refine | 6 | 6 | 0 | 4/6 | child_fit 3.83, classes 5.00, concreteness 4.67, coverage 3.50, precision 4.50 | 5/6 | 2.04s / 4.24s | $0.00046 |
| page_generate | 4 | 4 | 0 | 2/4 | child_fit 4.25, classes 4.50, concreteness 5.00, coverage 3.50, precision 4.25 | 3/4 | 3.06s / 3.85s | $0.00049 |
| page_refine | 3 | 3 | 0 | 3/3 | child_fit 4.67, classes 5.00, concreteness 5.00, coverage 4.67, precision 5.00 | 0/3 | 3.53s / 3.91s | $0.00042 |
| tile_suggest | 8 | 8 | 0 | 3/8 | child_fit 3.50, classes 4.62, concreteness 4.50, coverage 3.12, precision 4.12 | 6/8 | 1.68s / 2.79s | $0.00038 |
| moderation | 4 | 4 | 0 | 4/4 | — | 0/0 | 1.33s / 1.51s | $0.00007 |

## Worth a look (88)

- **sentence/dad_park_slide** #0: Dad, I want to play on the slide at the park.  
  intent=2; subject=1; stage_fit=2; naturalness=3
- **sentence/mom_cookie** #0: Mom, can I have a cookie?  
  intent=2; subject=2; stage_fit=2
- **sentence/outside** #0: I want to go outside.  
  intent=3; stage_fit=3
- **sentence/him_hit_me** #0: Him, hit me!  
  intent=1; subject=1; grammar=1; stage_fit=3; naturalness=1
- **sentence/her_pool** #0: Her, I want to go to the pool.  
  intent=1; subject=1; grammar=2; stage_fit=2; naturalness=1
- **sentence/pizza_eat_mom_scrambled** #0: Mom, I want to eat pizza.  
  intent=2; subject=1; stage_fit=2
- **sentence/tv_stop** #0: I want to stop the TV.  
  intent=3; stage_fit=3; naturalness=3
- **sentence/grandma_book** #0: Grandma, can I have a book?  
  intent=2; subject=2; stage_fit=2
- **sentence/i_bus_school** #0: I want the bus to school.  
  matches /want the bus/; intent=2; stage_fit=3; naturalness=3
- **sentence/she_pool** #0: She, I want to go to the pool.  
  chosen subject 'she' turned into a form of address; matches /^\s*she\s*,/; intent=1; subject=1; grammar=2; stage_fit=2; naturalness=1
- **sentence/he_find_raptor** #0: He, can you find a raptor?  
  chosen subject 'he' turned into a form of address; matches /^\s*he\s*,/; intent=2; subject=1; grammar=2; stage_fit=2; naturalness=2
- **sentence/they_play_ball** #0: They want to play ball.  
  intent=3; stage_fit=3
- **sentence/you_help_me** #0: Can you help me?  
  stage_fit=3
- **sentence/dad_eat_pizza** #0: Dad, I want to eat pizza.  
  intent=2; subject=1; stage_fit=2
- **sentence/we_park** #0: We want to go to the park.  
  intent=3; stage_fit=2
- **sentence/they_ball** #0: They want to play ball.  
  intent=3; stage_fit=3
- **sentence/he_raptor** #0: He is a raptor.  
  intent=2; naturalness=3
- **sentence/she_pizza** #0: She, I want pizza.  
  chosen subject 'she' turned into a form of address; matches /^\s*she\s*,/; intent=1; subject=1; grammar=1; stage_fit=3; naturalness=1
- **sentence/teacher_tired** #0: Teacher, I am tired.  
  intent=2; subject=2
- **sentence/mom_want_eat_pizza** #0: Mom, I want to eat pizza.  
  intent=2; subject=2; stage_fit=3
- **sentence/go_potty** #0: I want to go potty.  
  intent=3; stage_fit=3
- **sentence/find_ball** #0: I want to find a ball.  
  intent=3; stage_fit=3
- **sentence/take_bus** #0: I want to take the bus.  
  intent=3; stage_fit=3
- **sentence/i_like_dog** #0: I like dog.  
  grammar=3; stage_fit=3; naturalness=3
- **sentence/see_cat** #0: I want to see the cat.  
  intent=3; stage_fit=3
- **sentence/not_want_milk** #0: I want to drink milk.  
  negation lost; intent=1; stage_fit=3
- **sentence/no_bed** #0: No, I don't want bed.  
  matches /\bwant (to go )?(to )?(bed|sleep)/; intent=3; grammar=3; stage_fit=3; naturalness=3
- **sentence/no_house** #0: No, I want to go home.  
  matches /\bwant to go (home|to the house)/; intent=2; stage_fit=3
- **sentence/no_bed_no** #0: No, I don't want to go to bed. No!  
  matches /\bwant (to go )?(to )?(bed|sleep)/; intent=3; stage_fit=2
- **sentence/no_bath** #0: No, I don't want to wash.  
  intent=3; stage_fit=2
- **sentence/where_mom** #0: "Mom, where?"  
  not a question; intent=2; subject=2; grammar=2; stage_fit=3; naturalness=2
- **sentence/what_eat** #0: What can I eat?  
  intent=3; stage_fit=3
- **sentence/when_go_park** #0: When can we go to the park?  
  intent=3; subject=3; stage_fit=3
- **sentence/tomorrow_pool** #0: Tomorrow is a pool day.  
  intent=3; subject=3; stage_fit=3; naturalness=3
- **sentence/yesterday_park_play** #0: Yesterday was fun. I want to play at the park.  
  intent=1; stage_fit=2; naturalness=3
- **sentence/later_tv** #0: Later, the TV is on.  
  intent=2; subject=2; naturalness=3
- **sentence/again_swing** #0: I want to play again on the swing.  
  intent=3; stage_fit=2; naturalness=3
- **sentence/tired_bed_II-III** #0: I am tired. Can I go to bed?  
  intent=3; stage_fit=3
- **sentence/tired_bed_IV** #0: I am tired. Can I go to bed?  
  intent=3
- **sentence/mom_hungry_IV** #0: Mom, I am hungry.  
  intent=2; subject=1
- **sentence/go_outside_play_IV** #0: I want to go outside to play.  
  intent=3
- **sentence/she_pool_IV** #0: She, can we go to the pool?  
  chosen subject 'she' turned into a form of address; matches /^\s*she\s*,/; intent=1; subject=1; grammar=1; stage_fit=3; naturalness=1
- **sentence/dog_bite_me** #0: Dog, bite me!  
  intent=1; subject=2; stage_fit=3; naturalness=2
- **sentence/mom_head_hurt** #0: Mom, my head hurts.  
  intent=3; subject=2
- **sentence/teacher_sick** #0: Teacher, I am sick.  
  intent=2; subject=1
- **sentence/snack_bar_food** #0: I want a snack bar.  
  intent=3
- **sentence/orange_food** #0: I want to eat orange.  
  intent=3; grammar=3; stage_fit=3; naturalness=3
- **sentence/bowl_actions** #0: Dad, I want to bowl.  
  intent=2; subject=1; stage_fit=2
- **sentence/refine_question** #0: Mom, can I eat pizza?  
  stage_fit=3
- **sentence/refine_shorter** #0: I want to go to the park and play on the swing.  
  12 words, over 8; intent=3; stage_fit=2
- **escalation/chocolate** #0: I want chocolate. → I really want chocolate right now! → I really NEED chocolate right now! → I NEED CHOCOLATE NOW!!!  
  audible=3
- **escalation/mom_hungry** #0: Mom, I am hungry. → Mom, I am really hungry right now! → Mom, I am really hungry right now! → Mom, I am really hungry!  
  rung 3 less insistent than rung 2 (3 < 5); audible=2
- **escalation/watch_tv** #0: I want to watch TV. → I really want to watch TV right now! → I really NEED to watch TV right now! → I really NEED to watch TV right now! → I really NEED to watch TV right now!!!  
  audible=2
- **escalation/go_house** #0: I want to go to the house. → I want to go to the house right now! → I really NEED to go to the house right now! → I NEED to go to the HOUSE right now!  
  audible=3
- **escalation/mom_snack** #0: Mom, can I have chocolate milk and a graham cracker? → Mom, I really want chocolate milk and a graham cracker right now! → Mom, I really NEED chocolate milk and a graham cracker right now! → Mom, I NE  
  audible=3
- **escalation/she_pool** #0: She, I want to go to the pool. → She, I really want to go to the pool right now! → She, I really NEED to go to the pool right now! → She, I NEED to go to the pool NOW!!!  
  rung 0: chosen subject 'she' turned into a form of address; rung 1: chosen subject 'she' turned into a form of address; rung 2: chosen subject 'she' turned into a form of address; rung 3: chosen subject 'she' turned into a form of address; audible=3; grammar=2
- **escalation/where_mom** #0: "Mom, where?" → "Mom, where are we going?" → "Mom, where are we going?" → "Mom, where are we going?"  
  no escalation across the ladder (0 → 0); audible=1; same_want=1; grammar=3
- **escalation/stop_hit** #0: Stop hitting! → Stop hitting! Please! → Stop hitting! I really need it to stop right now! → Stop hitting! I really NEED it to STOP right now!  
  audible=2
- **escalation/chocolate_IV** #0: I want chocolate. → I really want chocolate right now! → I really NEED chocolate right now! → I want chocolate!  
  rung 3 less insistent than rung 2 (3 < 9); audible=2
- **scene_generate/potty_training** #0: (7 tiles)  
  1 undeclared key(s), dropped by the app: done; core-board word(s) on a topical page: bathroom, help; 7 tiles, under 12; missing 'flush'; missing 'wash / sink / soap'; coverage=3; precision=3
