# Eval run 2026-10-19-2020-gpt-4o-mini-p1-rejudge

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 1
- Commit `cabcc1c+dirty`, prompts `585b4e7282`, rubrics `129e37cc81`
- Samples per case: 3
- Cost: subject $0.0454, judge $0.7244

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 67 | 201 | 0 | 201/201 | grammar 5.00, intent 4.90, naturalness 4.95, stage_fit 5.00, subject 4.96 | 12/201 | 0.79s / 1.03s | $0.00013 |
| escalation | 9 | 27 | 0 | 12/27 | audible 2.70, grammar 5.00, same_want 4.78 | 22/27 | 0.81s / 1.14s | $0.00075 |

## Worth a look (36)

- **sentence/tv_stop** #0: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #1: I want to stop the TV.  
  naturalness=3
- **sentence/tv_stop** #2: I want to stop the TV.  
  naturalness=3
- **sentence/he_raptor** #0: He is a raptor!  
  intent=2; naturalness=3
- **sentence/he_raptor** #1: He is a raptor!  
  intent=3
- **sentence/he_raptor** #2: He is a raptor!  
  intent=2; naturalness=3
- **sentence/where_mom** #0: Where is Mom?  
  intent=3; subject=3
- **sentence/where_mom** #1: Where is Mom?  
  intent=3; subject=2
- **sentence/where_mom** #2: Where is Mom?  
  intent=3; subject=2
- **sentence/history_more** #0: Please, I want more.  
  intent=3
- **sentence/history_more** #1: Please, I want more.  
  intent=3
- **sentence/history_more** #2: Please, I want more.  
  intent=3
- **escalation/want_chocolate** #0: I want to eat chocolate. → I really want to eat chocolate right now! → I really want to eat chocolate right now! → I really want to eat chocolate right now!  
  rung 2 repeats rung 1; rung 3 repeats rung 2; audible=3
- **escalation/want_chocolate** #1: I want to eat chocolate. → I really want to eat chocolate right now! → I really want to eat chocolate right now! → I really WANT to eat CHOCOLATE right now!!!  
  rung 2 repeats rung 1; audible=3
- **escalation/want_chocolate** #2: I want to eat chocolate. → I really want to eat chocolate right now! → I really NEED to eat chocolate right now! → I want to eat chocolate!  
  rung 3 less insistent than rung 2 (3 < 9); audible=2
- **escalation/mom_hungry** #0: Mom, I am hungry. → Mom, I am really hungry right now! → Mom, I am really hungry! Can I eat something? → Mom, I am really hungry! Can I eat something right now?  
  rung 2 less insistent than rung 1 (3 < 5)
- **escalation/mom_hungry** #1: Mom, I am hungry. → Mom, I am really hungry right now! → Mom, I am really hungry right now! I need food! → Mom, I am really hungry! Can I eat?  
  rung 3 less insistent than rung 2 (3 < 8); audible=3
- **escalation/mom_hungry** #2: Mom, I am hungry. → Mom, I am really hungry right now! → Mom, I am really hungry right now! → Mom, I am SO hungry! I need to eat NOW!!!  
  rung 2 repeats rung 1
- **escalation/watch_tv** #0: I want to watch TV. → I really want to watch TV right now! → I really NEED to watch TV right now! → I NEED to WATCH TV right now!!! → I WANT to WATCH TV NOW!!!  
  audible=3
- **escalation/watch_tv** #1: I want to watch TV. → I really want to watch TV right now! → I really NEED to watch TV right now! → I WANT to WATCH TV NOW!!! → I WANT to WATCH TV RIGHT NOW!!!  
  audible=3
- **escalation/watch_tv** #2: I want to watch TV. → I really want to watch TV right now! → I really NEED to watch TV right now! → I NEED to WATCH TV right now!!! → I WANT to WATCH TV NOW!!!  
  audible=3
- **escalation/go_house** #0: I want to go to the house. → I really want to go to the house right now! → I really NEED to go to the house right now! → I WANT to go to the HOUSE NOW!!!  
  audible=3
- **escalation/go_house** #1: I want to go to the house. → I really want to go to the house right now! → I really NEED to go to the house right now! → I WANT to go to the HOUSE NOW!!!  
  audible=3
- **escalation/go_house** #2: I want to go to the house. → I really want to go to the house right now! → I really NEED to go to the house right now! → I WANT to go to the HOUSE NOW!!!  
  audible=3
- **escalation/mom_snack** #0: Mom, can I have chocolate milk and a graham cracker? → Mom, I really need chocolate milk and a graham cracker right now! → MOM! I REALLY NEED CHOCOLATE MILK AND A GRAHAM CRACKER RIGHT NOW!!! → MOM! I   
  rung 3 repeats rung 2; audible=3
- **escalation/mom_snack** #1: Mom, can I have chocolate milk and a graham cracker? → Mom, I really need chocolate milk and a graham cracker right now! → Mom, I really NEED chocolate milk and a graham cracker right now! → MOM! I NE  
  audible=3
- **escalation/mom_snack** #2: Mom, can I have chocolate milk and a graham cracker? → Mom, I really need chocolate milk and a graham cracker right now! → Mom, I really NEED chocolate milk and a graham cracker right now! → Mom, I NE  
  audible=3
- **escalation/she_pool** #0: She is at the pool. → She is at the pool right now! → She is at the pool right now! → She is at the pool right now!  
  rung 2 repeats rung 1; rung 3 repeats rung 2; audible=1
- **escalation/she_pool** #1: She is at the pool. → She is at the pool right now! → She is at the pool right now! I really need to go to the pool! → She is at the pool! I really need to go to the pool right now!  
  audible=2; same_want=1
- **escalation/she_pool** #2: She is at the pool. → She is at the pool right now! → She is at the pool right now! → She is at the pool right now!  
  rung 2 repeats rung 1; rung 3 repeats rung 2; audible=2
- **escalation/where_mom** #0: Where is Mom? → Where is Mom? I need her now! → Mom, where are you? I need you now! → Mom, where are you?  
  rung 3 less insistent than rung 2 (0 < 4); no escalation across the ladder (0 → 0); audible=2
- **escalation/where_mom** #1: Where is Mom? → Mom, where are you? → Mom, where are you? → Mom, where are you?  
  rung 2 repeats rung 1; rung 3 repeats rung 2; no escalation across the ladder (0 → 0); audible=1
- **escalation/where_mom** #2: Mom, where are you? → Mom, where are you? → Mom, where are you? → Mom, where are you?  
  rung 1 repeats rung 0; rung 2 repeats rung 1; rung 3 repeats rung 2; no escalation across the ladder (0 → 0); audible=1
- **escalation/want_chocolate_IV** #0: I want to eat chocolate. → I really want to eat chocolate right now! → I really want to eat chocolate right now! → I really want to eat chocolate right now!  
  rung 2 repeats rung 1; rung 3 repeats rung 2; audible=2
- **escalation/want_chocolate_IV** #1: I want to eat chocolate. → I really want to eat chocolate right now! → I really NEED to eat chocolate right now! → I want to eat chocolate!  
  rung 3 less insistent than rung 2 (3 < 9); audible=2
- **escalation/want_chocolate_IV** #2: I want to eat chocolate. → I really want to eat chocolate right now! → I really NEED to eat chocolate right now! → I want to eat chocolate!  
  rung 3 less insistent than rung 2 (3 < 9); audible=2
