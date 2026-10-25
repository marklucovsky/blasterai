# Eval run 2026-10-24-1712-gpt-6-luna-none-vehicle-fix3

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `b8c48a8+dirty`, prompts `e0f770abe9`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.0469, judge $0.4994

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 78 | 234 | 0 | 226/234 | grammar 4.97, intent 4.88, naturalness 4.97, stage_fit 4.93, subject 4.99 | 17/234 | 0.95s / 1.33s | $0.00003 |
| escalation | 13 | 39 | 0 | 37/39 | audible 4.85, grammar 5.00, same_want 4.85 | 2/39 | 1.10s / 1.52s | $0.00100 |

## Worth a look (23)

- **sentence/dad_park_slide** #0: Dad, can I go play at the park and go down the slide?  
  13 words, over 12 for Stage II-III; stage_fit=3
- **sentence/tv_stop** #2: Stop watching TV!  
  intent=3; subject=3
- **sentence/find_ball** #0: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/no_bed_no** #0: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #1: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #2: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/tired_bed_II-III** #0: I'm tired. I want a bed.  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #0: I hurt my stomach.  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #2: I hurt my stomach.  
  intent=3; naturalness=3
- **sentence/history_more** #0: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #1: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #2: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/refine_shorter** #0: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #1: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #2: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/i_police_car_officer** #0: Police officer, can I ride in the police car with you?  
  intent=3
- **sentence/i_fire_truck** #0: I want to ride in the fire truck.  
  intent=3
- **sentence/i_fire_truck** #1: I want to ride in the fire truck.  
  intent=3
- **sentence/i_fire_truck** #2: I want to ride in the fire truck.  
  intent=3
- **sentence/toy_car_want** #2: I want a toy and to ride in the car.  
  intent=2; stage_fit=3; naturalness=3
- **escalation/mom_hungry** #0: Mom, I am hungry. Can I have something to eat? → Mom, I am really hungry! Can I please have something to eat right now? → Mom, I am really, really hungry! I need to eat right now, please! → Mom, I am   
  audible=3
- **escalation/she_pool** #1: She wants to go to the pool. → Listen! She IS at the pool! → Listen to me! She IS at the pool, right now! → Listen to me! She IS at the pool, right now!  
  rung 3 repeats rung 2; audible=3; same_want=1
- **escalation/she_pool** #2: She is going to the pool. → Listen! She IS going to the pool! → Listen to me! She IS going to the pool, right now! → Listen to me! She IS going to the pool, right now!  
  rung 3 repeats rung 2
