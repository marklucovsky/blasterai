# Eval run 2026-10-26-0944-gpt-6-luna-none-classes-before

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `9dd8c24+dirty`, prompts `033c9d88c3`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.0062, judge $0.1956

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 25 | 75 | 0 | 74/75 | grammar 4.92, intent 4.76, naturalness 4.97, stage_fit 4.92, subject 5.00 | 9/75 | 1.22s / 2.40s | $0.00004 |
| escalation | 1 | 3 | 0 | 2/3 | audible 4.67, grammar 5.00, same_want 5.00 | 0/3 | 1.17s / 1.58s | $0.00103 |

## Worth a look (10)

- **sentence/history_more** #0: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #1: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/history_more** #2: More, please.  
  intent=3; grammar=3; stage_fit=3
- **sentence/i_police_car_officer** #0: Police Officer, I want to ride in the police car with you.  
  intent=3
- **sentence/i_police_car_officer** #2: Officer, I ride in the police car with you.  
  intent=3; naturalness=3
- **sentence/i_fire_truck** #0: I want to ride in the fire truck.  
  intent=3
- **sentence/i_fire_truck** #1: I want to ride in the fire truck.  
  intent=3
- **sentence/i_fire_truck** #2: I want to ride in the fire truck.  
  intent=3
- **sentence/i_ambulance** #2: I want to ride in the ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/; intent=3
- **escalation/he_hit_me** #2: He hit me! → Help! He hit me! It really hurt! → Help me, please! He hit me! It really, really hurt! → Help me, please! He hit me! It really, really hurt!  
  rung 3 repeats rung 2
