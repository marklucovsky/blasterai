# Eval run 2026-10-21-1907-gpt-6-luna-none-l6-ship

- Subject: `gpt-6-luna` (effort `none`)
- Judge: `gpt-6.1-sol` × 3
- Commit `007f674+dirty`, prompts `cd9854217d`, rubrics `fc770a3add`
- Samples per case: 5
- Cost: subject $0.0638, judge $2.1311

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 71 | 355 | 0 | 342/355 | grammar 4.97, intent 4.87, naturalness 4.96, stage_fit 4.95, subject 4.97 | 26/355 | 1.07s / 1.99s | $0.00003 |
| escalation | 13 | 65 | 0 | 60/65 | audible 4.83, grammar 5.00, same_want 4.88 | 4/65 | 1.19s / 1.96s | $0.00082 |

## Worth a look (40)

- **sentence/dad_park_slide** #2: Dad, I want to go to the park and play on the slide.  
  13 words, over 12 for Stage II-III
- **sentence/dad_park_slide** #3: Dad, I want to go to the park and play on the slide.  
  13 words, over 12 for Stage II-III
- **sentence/tv_stop** #0: Stop watching TV.  
  intent=3; subject=3
- **sentence/tv_stop** #1: Stop watching TV.  
  intent=3; subject=3
- **sentence/tv_stop** #2: Stop watching TV.  
  intent=3; subject=3
- **sentence/tv_stop** #3: Stop watching TV.  
  intent=3; subject=3
- **sentence/tv_stop** #4: Stop watching TV.  
  intent=3; subject=3
- **sentence/he_find_raptor** #4: He is finding a raptor.  
  naturalness=3
- **sentence/find_ball** #0: Can I find a ball to play with?  
  intent=3
- **sentence/find_ball** #1: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #2: Can I find a ball to play with?  
  intent=3
- **sentence/find_ball** #3: I want to play ball.  
  missing 'find / where'; intent=2
- **sentence/find_ball** #4: Can I find a ball game?  
  intent=2; naturalness=3
- **sentence/no_bed** #1: No! I don't want the bed.  
  intent=3; naturalness=3
- **sentence/no_bed** #2: No! I don’t want the bed.  
  naturalness=3
- **sentence/no_bed_no** #0: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #1: No! I don’t want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #2: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/no_bed_no** #3: No! I don't want to go to bed. No!  
  3 sentences; stage_fit=3
- **sentence/tired_bed_II-III** #0: I’m tired. I want the bed.  
  intent=3; naturalness=3
- **sentence/hurt_stomach** #1: I hurt my stomach.  
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
- **sentence/bowl_actions** #2: Dad, can I have a bowl?  
  intent=2
- **sentence/bowl_actions** #4: Dad, can I have a bowl?  
  intent=2
- **sentence/refine_shorter** #0: Can I go to the park and play on the swing?  
  11 words, over 10
- **sentence/refine_shorter** #1: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #2: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #3: I want to go to the park and play on the swings.  
  12 words, over 10
- **sentence/refine_shorter** #4: I want to go to the park and play on the swings.  
  12 words, over 10
- **escalation/mom_hungry** #0: Mom, I am hungry. → Mom, I am really hungry! I need something to eat right now, please! → Mom, I am really, really hungry! I need something to eat right now, please! I can't wait! → Mom, I am really,   
  audible=3
- **escalation/she_pool** #0: She wants to go to the pool. → She really wants to go to the pool right now, please! → She really needs to go to the pool right now, please! → Listen to me! She is at the pool, right now!  
  rung 3 less insistent than rung 2 (6 < 7); audible=3; same_want=2
- **escalation/she_pool** #4: She wants to go to the pool. → She really wants to go to the pool right now, please! → She really needs to go to the pool right now, please! → Listen to me! She is at the pool right now!  
  rung 3 less insistent than rung 2 (6 < 7); audible=3; same_want=2
- **escalation/where_mom** #0: Where is Mom? → Where is Mom? I need to know right now! → Please, where is Mom? I really need to know right now! → Please, where is Mom? I really need to know right now! → Please, where is Mom? I real  
  rung 3 repeats rung 2
- **escalation/what_eat** #3: What can I eat? → What can I eat? What I eat really matters! → What can I eat? I really need to eat right now! → Please, what can I eat? I really need to eat right now! → Please, what can I eat? I rea  
  same_want=3
- **escalation/he_hit_me** #4: He hit me. → Help! He hit me! It really hurt! → Help me, please! He hit me! It really, really hurt! → Help me, please! He hit me! It really, really hurt!  
  rung 3 repeats rung 2
- **escalation/stop_hit** #1: Stop hitting! → Stop hitting right now! Please stop! → Stop it! Stop hitting right now! Please, stop! → Stop it! Stop hitting right now! Please, stop!  
  rung 3 repeats rung 2
