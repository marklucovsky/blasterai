# Eval run 2026-10-24-1705-gpt-6-luna-none-vehicle-base

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `b8c48a8+dirty`, prompts `31e268342b`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.0079, judge $0.6150

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 78 | 234 | 0 | 214/234 | grammar 4.97, intent 4.82, naturalness 4.94, stage_fit 4.94, subject 4.97 | 23/234 | 1.01s / 1.87s | $0.00003 |

## Worth a look (37)

- **sentence/dad_park_slide** #2: Dad, can I play at the park and go down the slide?  
  stage_fit=3
- **sentence/tv_stop** #0: Stop watching TV!  
  intent=3; subject=3
- **sentence/tv_stop** #1: Stop watching TV!  
  intent=3; subject=3
- **sentence/tv_stop** #2: Stop watching TV!  
  intent=3; subject=3
- **sentence/find_ball** #0: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #1: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #2: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/no_bed** #0: No! I don’t want the bed.  
  intent=3; naturalness=3
- **sentence/no_bed** #2: No! I don’t want the bed.  
  intent=3; naturalness=3
- **sentence/no_bed_no** #0: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #1: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #2: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/tired_bed_II-III** #1: I’m tired. Can I have the bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_IV** #1: I'm tired. Can I have the bed?  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #1: I hurt my stomach.  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #2: I hurt my stomach.  
  intent=3; naturalness=3
- **sentence/history_more** #0: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #1: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #2: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/bowl_actions** #1: Dad, can I have a bowl?  
  intent=2
- **sentence/bowl_actions** #2: Dad, can I have a bowl?  
  intent=2
- **sentence/refine_shorter** #0: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #1: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #2: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/i_police_car_officer** #0: Police officer, can I have a police car?  
  does not match /ride|riding|go|drive|in the police car/; matches /have a police car|want a police car|get a police car/
- **sentence/i_police_car_officer** #1: Police officer, I want the police car.  
  does not match /ride|riding|go|drive|in the police car/
- **sentence/i_police_car_officer** #2: Police officer, I want the police car.  
  does not match /ride|riding|go|drive|in the police car/
- **sentence/i_fire_truck** #1: I want a fire truck.  
  matches /have a fire truck|want a fire truck|get a fire truck/
- **sentence/i_fire_truck** #2: I want a fire truck.  
  matches /have a fire truck|want a fire truck|get a fire truck/
- **sentence/i_boat** #0: I want a boat.  
  matches /have a boat|want a boat|get a boat/
- **sentence/i_boat** #1: I want a boat.  
  matches /have a boat|want a boat|get a boat/
- **sentence/i_boat** #2: I want a boat.  
  matches /have a boat|want a boat|get a boat/
- **sentence/i_ambulance** #0: I want an ambulance.  
  matches /have an ambulance|want an ambulance|fun/
- **sentence/i_ambulance** #1: I want an ambulance.  
  matches /have an ambulance|want an ambulance|fun/
- **sentence/i_ambulance** #2: I want an ambulance.  
  matches /have an ambulance|want an ambulance|fun/
- **sentence/toy_car_want** #0: I want a toy and a car.  
  intent=3
- **sentence/toy_car_want** #2: I want a toy and a car.  
  intent=3
