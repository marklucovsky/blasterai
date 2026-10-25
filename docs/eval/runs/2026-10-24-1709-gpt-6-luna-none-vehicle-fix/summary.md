# Eval run 2026-10-24-1709-gpt-6-luna-none-vehicle-fix

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `b8c48a8+dirty`, prompts `4d5231aaa6`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.0082, judge $0.3799

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 78 | 234 | 0 | 212/234 | grammar 4.97, intent 4.88, naturalness 4.94, stage_fit 4.96, subject 4.99 | 15/234 | 0.99s / 1.41s | $0.00004 |

## Worth a look (33)

- **sentence/tv_stop** #0: Stop watching TV.  
  intent=3; subject=3
- **sentence/find_ball** #0: I find the ball.  
  intent=3; naturalness=3
- **sentence/find_ball** #1: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #2: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/no_bed** #0: No! I don’t want the bed.  
  intent=3; naturalness=3
- **sentence/no_bed_no** #0: No! I don’t want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #2: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/tired_bed_II-III** #2: I'm tired. Can I have the bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_IV** #0: I’m tired. Can I have the bed?  
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
- **sentence/refine_shorter** #0: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #1: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #2: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/i_police_car_officer** #0: Police officer, I want a police car.  
  does not match /ride|riding|go|drive|in the police car/; matches /(have|want|get) (a|an|the|my) police car\b/
- **sentence/i_police_car_officer** #1: Police officer, I want the police car.  
  does not match /ride|riding|go|drive|in the police car/; matches /(have|want|get) (a|an|the|my) police car\b/
- **sentence/i_police_car_officer** #2: Police officer, I want the police car.  
  does not match /ride|riding|go|drive|in the police car/; matches /(have|want|get) (a|an|the|my) police car\b/
- **sentence/i_fire_truck** #0: I want a fire truck.  
  matches /(have|want|get) (a|an|the|my) fire truck\b/
- **sentence/i_fire_truck** #1: I want a fire truck.  
  matches /(have|want|get) (a|an|the|my) fire truck\b/
- **sentence/i_fire_truck** #2: I want a fire truck.  
  matches /(have|want|get) (a|an|the|my) fire truck\b/
- **sentence/mom_car** #0: Mom, can I have the car?  
  matches /(have|want|get) (a|an|the|my) car\b/
- **sentence/mom_car** #1: Mom, can I have the car?  
  matches /(have|want|get) (a|an|the|my) car\b/
- **sentence/mom_car** #2: Mom, can I have the car?  
  matches /(have|want|get) (a|an|the|my) car\b/
- **sentence/i_boat** #0: I want a boat.  
  matches /(have|want|get) (a|an|the|my) boat\b/
- **sentence/i_boat** #1: I want a boat.  
  matches /(have|want|get) (a|an|the|my) boat\b/
- **sentence/i_boat** #2: I want the boat.  
  matches /(have|want|get) (a|an|the|my) boat\b/
- **sentence/i_ambulance** #0: I want the ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/
- **sentence/i_ambulance** #1: I want an ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/
- **sentence/i_ambulance** #2: I want an ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/
- **sentence/toy_car_want** #0: I want a toy and a car.  
  intent=3
