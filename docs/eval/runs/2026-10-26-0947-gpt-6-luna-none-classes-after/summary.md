# Eval run 2026-10-26-0947-gpt-6-luna-none-classes-after

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `9dd8c24+dirty`, prompts `033c9d88c3`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.0036, judge $0.2012

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 25 | 75 | 0 | 73/75 | grammar 4.92, intent 4.71, naturalness 4.99, stage_fit 4.92, subject 4.89 | 11/75 | 1.11s / 2.10s | $0.00003 |
| escalation | 1 | 3 | 0 | 3/3 | audible 4.67, grammar 5.00, same_want 5.00 | 0/3 | 1.09s / 1.36s | $0.00046 |

## Worth a look (12)

- **sentence/history_more** #0: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #1: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #2: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/i_police_car_officer** #0: I ride in the police car with the police officer.  
  intent=3; subject=3
- **sentence/i_police_car_officer** #1: I ride in the police car with the police officer.  
  intent=3; subject=2
- **sentence/i_police_car_officer** #2: I ride in the police car with the police officer.  
  intent=3; subject=2
- **sentence/i_fire_truck** #0: I want to ride in the fire truck.  
  intent=3
- **sentence/i_fire_truck** #1: I want to ride in the fire truck.  
  intent=3
- **sentence/i_fire_truck** #2: I want to ride in the fire truck.  
  intent=3
- **sentence/i_ambulance** #0: I want to ride in the ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/
- **sentence/i_ambulance** #1: I see an ambulance.  
  intent=3
- **sentence/i_ambulance** #2: I ride in an ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/; intent=3
