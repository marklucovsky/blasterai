# Eval run 2026-10-21-1639-gpt-6-luna-none-luna-vs-baseline-rejudge

- Subject: `gpt-6-luna` (effort `none`)
- Judge: none
- Commit `660c8d0+dirty`, prompts `9382d07e6c`, rubrics `fc770a3add`
- Samples per case: 5
- Cost: subject $0.0541, judge $2.3856

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 70 | 350 | 0 | 329/350 | grammar 4.89, intent 4.62, naturalness 4.76, stage_fit 4.91, subject 4.92 | 58/350 | 1.06s / 1.55s | $0.00002 |
| escalation | 13 | 65 | 0 | 46/65 | audible 4.45, grammar 5.00, same_want 3.98 | 21/65 | 1.11s / 1.58s | $0.00071 |

## Worth a look (95)

- **sentence/dad_park_slide** #0: Dad, I want to play at the park.  
  missing 'slide / slides'; intent=3
- **sentence/dad_park_slide** #2: Dad, I want to play at the park.  
  missing 'slide / slides'; intent=3
- **sentence/dad_park_slide** #3: Dad, I want to play at the park.  
  missing 'slide / slides'; intent=3
- **sentence/her_pool** #0: Can we go to the pool?  
  intent=2; subject=1
- **sentence/her_pool** #1: Her, can I go to the pool?  
  intent=2; subject=1; grammar=2; naturalness=2
- **sentence/her_pool** #2: Her, I want to go to the pool.  
  intent=2; subject=1; grammar=2; naturalness=2
- **sentence/her_pool** #3: Her, I want to go to the pool.  
  intent=2; subject=1; grammar=2; naturalness=2
- **sentence/her_pool** #4: Her, I want to go to the pool.  
  intent=2; subject=1; grammar=2; naturalness=2
- **sentence/tv_stop** #1: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #2: Can I stop the TV?  
  intent=3; naturalness=3
- **sentence/tv_stop** #3: I want to stop the TV.  
  naturalness=3
- **sentence/yes_no** #0: Yes, no.  
  intent=3; grammar=2; stage_fit=3; naturalness=3
- **sentence/yes_no** #1: Yes, no.  
  intent=3; grammar=2; stage_fit=3; naturalness=2
- **sentence/yes_no** #2: Yes, no.  
  intent=3; grammar=2; stage_fit=3; naturalness=2
- **sentence/yes_no** #3: Yes, no.  
  intent=3; grammar=2; stage_fit=3; naturalness=2
- **sentence/yes_no** #4: Yes, no.  
  intent=3; grammar=2; stage_fit=3; naturalness=2
- **sentence/i_bus_school** #0: I want the bus to go to school.  
  matches /want the bus/; intent=3; stage_fit=3; naturalness=3
- **sentence/i_bus_school** #1: I want a bus to go to school.  
  intent=3; naturalness=3
- **sentence/i_bus_school** #2: I want the bus to go to school.  
  matches /want the bus/; intent=3; stage_fit=3; naturalness=3
- **sentence/i_bus_school** #3: I want the bus to go to school.  
  matches /want the bus/; intent=3; stage_fit=3; naturalness=3
- **sentence/i_bus_school** #4: I want the bus to go to school.  
  matches /want the bus/; intent=3; subject=3; stage_fit=3; naturalness=3
- **sentence/you_help_me** #0: Help me.  
  missing 'you'
- **sentence/you_help_me** #4: Help me, please.  
  missing 'you'
- **sentence/go_potty** #0: I am going potty.  
  intent=3
- **sentence/find_ball** #0: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #3: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/stop_hit** #1: I want to stop hitting.  
  intent=2; subject=2; naturalness=3
- **sentence/stop_hit** #2: I want to stop hitting.  
  intent=2; subject=2; naturalness=3
- **sentence/no_bed** #0: No, I want a bed.  
  intent=1
- **sentence/no_bed** #1: No, I want the bed.  
  intent=1
- **sentence/no_bed** #2: No, I want the bed.  
  intent=1
- **sentence/no_bed** #3: No, I want to go to bed.  
  matches /(?<!n't )(?<!not )\bwant (to go )?(to )?(bed|sleep)/; intent=1
- **sentence/no_bed** #4: No bed, please.  
  grammar=3; stage_fit=3; naturalness=3
- **sentence/no_house** #0: No, I want to go to the house.  
  matches /(?<!n't )(?<!not )\bwant to go (home|to the house)/; intent=2
- **sentence/no_house** #1: No, I want to go home.  
  matches /(?<!n't )(?<!not )\bwant to go (home|to the house)/; intent=2
- **sentence/no_house** #2: No! I want to go home.  
  matches /(?<!n't )(?<!not )\bwant to go (home|to the house)/; intent=2
- **sentence/no_house** #3: No, I’m at the house.  
  intent=2; naturalness=3
- **sentence/no_house** #4: No, I want to go home.  
  matches /(?<!n't )(?<!not )\bwant to go (home|to the house)/; intent=2
- **sentence/no_bed_no** #0: No, I don't want the bed. No.  
  intent=3; naturalness=3
- **sentence/no_bed_no** #1: No, I don’t want the bed. No.  
  intent=3; naturalness=3
- **sentence/no_bed_no** #2: No, I don’t want the bed. No.  
  intent=3; stage_fit=3; naturalness=3
- **sentence/no_bed_no** #3: No, I don’t want the bed.  
  intent=3; naturalness=3
- **sentence/no_bed_no** #4: No, I don’t want the bed.  
  intent=3; naturalness=3
- **sentence/no_bath** #4: No, I want to wash.  
  intent=1
- **sentence/what_eat** #1: What do I want to eat?  
  intent=3; naturalness=3
- **sentence/what_eat** #4: What do I want to eat?  
  intent=3; naturalness=3
- **sentence/dog_in_car** #4: I want a dog in the car.  
  intent=3
- **sentence/tired_bed_II-III** #0: I’m tired. Can I have my bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_II-III** #1: I’m tired. Can I have my bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_II-III** #2: I'm tired. Can I have my bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_II-III** #3: I'm tired. Can I have my bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_IV** #0: I’m tired. Can I have a bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_IV** #2: I’m tired. Can I have my bed?  
  intent=3; naturalness=3
- **sentence/tired_bed_IV** #3: I’m tired. Can I have my bed?  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #2: I hurt my stomach.  
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
