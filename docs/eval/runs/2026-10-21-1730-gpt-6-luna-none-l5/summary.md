# Eval run 2026-10-21-1730-gpt-6-luna-none-l5

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 3
- Commit `660c8d0+dirty`, prompts `e41fa53658`, rubrics `fc770a3add`
- Samples per case: 5
- Cost: subject $0.0612, judge $2.1278

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 70 | 350 | 0 | 335/350 | grammar 4.97, intent 4.89, naturalness 4.96, stage_fit 4.94, subject 4.99 | 24/350 | 0.93s / 1.40s | $0.00003 |
| escalation | 13 | 65 | 0 | 53/65 | audible 4.72, grammar 5.00, same_want 4.75 | 9/65 | 1.06s / 1.53s | $0.00078 |

## Worth a look (46)

- **sentence/dad_park_slide** #1: Dad, I want to play at the park and go down the slide.  
  13 words, over 12 for Stage II-III
- **sentence/tv_stop** #1: Stop watching TV!  
  intent=3; subject=3
- **sentence/he_find_raptor** #2: He is finding a raptor.  
  naturalness=3
- **sentence/find_ball** #0: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #1: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #2: I want to find a ball to play with.  
  intent=3
- **sentence/find_ball** #3: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #4: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/no_bed** #4: No! I don’t want the bed.  
  intent=3; naturalness=3
- **sentence/no_bed_no** #0: No! No! I don’t want to go to bed.  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #1: No! I don’t want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #2: No! I don’t want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #3: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #4: No! I don’t want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bath** #0: No! Don't wash!  
  intent=3; subject=3
- **sentence/dog_in_car** #0: I want a dog in the car.  
  intent=3
- **sentence/tired_bed_II-III** #0: I’m tired. I want the bed.  
  intent=3; naturalness=3
- **sentence/tired_bed_IV** #0: I’m tired, and I want the bed.  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #1: I hurt my stomach.  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #3: I hurt my stomach.  
  intent=3; naturalness=3
- **sentence/history_more** #0: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #1: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #2: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #3: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #4: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/refine_shorter** #0: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #1: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #2: Can I go to the park and play on the swing?  
  11 words, over 10
- **sentence/refine_shorter** #3: I want to go to the park and play on the swing.  
  12 words, over 10
- **sentence/refine_shorter** #4: I want to go to the park and play on the swings.  
  12 words, over 10
- **escalation/watch_tv** #3: I watch TV. → I really want to watch TV right now, please! → I really NEED to watch TV right now, please! → I really, really NEED to watch TV right now! Please, please! I can't wait! → I really, reall  
  same_want=2
- **escalation/she_pool** #0: She is going to the pool. → Listen! She IS going to the pool! → Listen to me! She IS going to the pool, right now! → Listen to me! She IS going to the pool, right now!  
  rung 3 repeats rung 2
- **escalation/she_pool** #1: She is going to the pool. → Listen! She IS going to the pool! → Listen! She IS going to the pool! → Listen to me! She IS at the pool right now!  
  rung 2 repeats rung 1; same_want=3
- **escalation/she_pool** #2: She is going to the pool. → Listen! She IS going to the pool! → Listen to me! She IS going to the pool, right now! → Listen to me! She IS going to the pool, right now!  
  rung 3 repeats rung 2
- **escalation/she_pool** #4: She is going to the pool. → Listen! She IS going to the pool! → Listen to me! She IS going to the pool right now! → Listen to me! She IS going to the pool right now! I can't wait!  
  same_want=3
- **escalation/where_mom** #1: Where is Mom? → Where is Mom? I really need to know right now! → Where is Mom? I really need to know right now! → Please, where is Mom? I really need to know right now! → Please, where is Mom? I reall  
  rung 2 repeats rung 1
- **escalation/where_mom** #3: Where is Mom? → Where is Mom? I really need to know right now! → Where is Mom? I really need to know right now! I need to know right now! → Please, where is Mom? I really need to know right now! → Ple  
  rung 3 less insistent than rung 2 (7 < 8); audible=3
- **escalation/what_eat** #2: What can I eat? → What can I eat? I really need to eat right now, please! → What can I eat? I really need to eat right now, please! I can’t wait! → Please, what can I eat? I really need to eat right n  
  rung 2: matches /can't wait/; rung 3 less insistent than rung 2 (7 < 9); audible=3
- **escalation/he_hit_me** #0: He hit me. → Listen! He IS hitting me right now! → Listen! He IS hitting me right now! → Listen to me! He IS hitting me right now!  
  rung 2 repeats rung 1; same_want=3
- **escalation/he_hit_me** #1: He hit me! → Help! He hit me! It really hurt! → Help! He hit me! It really hurt! → Help me, please! He hit me! It really, really hurt!  
  rung 2 repeats rung 1
- **escalation/he_hit_me** #4: He hit me. → He IS hitting me! → Listen! He IS hitting me! → Listen to me! He IS hitting me, right now!  
  same_want=3
- **escalation/stop_hit** #1: Stop hitting! → Stop hitting right now! Please stop! → Stop it! Stop hitting right now! Please, stop! → Stop it! Stop hitting right now! Please, stop!  
  rung 3 repeats rung 2
- **escalation/stop_hit** #3: Stop hitting! → Stop hitting right now! Please stop! → Stop it! Stop hitting right now! Please, stop! → Stop it! Stop hitting right now! Please, stop!  
  rung 3 repeats rung 2
- **escalation/no_home** #1: No, I don’t want to go home. → No, no! I really don’t want to go home right now! → No, no! I really, really don’t want to go home right now! Please, no! → No, no, no! I really, really don’t want to go  
  rung 3 less insistent than rung 2 (9 < 11)
- **escalation/no_home** #2: No, I don't want to go home. → No, no! I really don't want to go home right now! → No, no! I really don't want to go home right now! I need to stay here! → No, no, no! I really, really don't want to g  
  rung 3 less insistent than rung 2 (9 < 11); audible=3; same_want=3
- **escalation/want_chocolate_IV** #4: I want some chocolate. → I really want some chocolate right now, please! → I really NEED some chocolate right now, please! → I really, really NEED to want chocolate right now! Please, please! I can't   
  same_want=2
