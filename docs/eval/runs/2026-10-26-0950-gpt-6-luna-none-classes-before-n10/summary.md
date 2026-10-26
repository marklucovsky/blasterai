# Eval run 2026-10-26-0950-gpt-6-luna-none-classes-before-n10

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 1
- Commit `9dd8c24+dirty`, prompts `033c9d88c3`, rubrics `fc770a3add`
- Samples per case: 10
- Cost: subject $0.0006, judge $0.0407

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 2 | 20 | 0 | 19/20 | grammar 5.00, intent 4.30, naturalness 5.00, stage_fit 5.00, subject 5.00 | 7/20 | 1.36s / 1.96s | $0.00003 |

## Worth a look (7)

- **sentence/i_police_car_officer** #0: Police Officer, I want to ride in the police car with you.  
  intent=3
- **sentence/i_police_car_officer** #1: Police officer, I want to ride in the police car with you.  
  intent=3
- **sentence/i_police_car_officer** #3: Police Officer, can I ride in the police car with you?  
  intent=3
- **sentence/i_police_car_officer** #4: Police Officer, I want to ride in the police car with you.  
  intent=3
- **sentence/i_police_car_officer** #5: Police Officer, can I ride in the police car with you?  
  intent=3
- **sentence/i_police_car_officer** #7: Police officer, I want to ride in the police car with you.  
  intent=3
- **sentence/i_ambulance** #2: I want to ride in the ambulance.  
  matches /(have|want|get) (a|an|the) ambulance|fun|ride in/; intent=3
