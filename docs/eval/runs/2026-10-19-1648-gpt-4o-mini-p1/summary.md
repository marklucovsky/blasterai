# Eval run 2026-10-19-1648-gpt-4o-mini-p1

- Subject: `gpt-4o-mini`
- Judge: none
- Commit `70173e5+dirty`, prompts `91753ce058`, rubrics `90c6a0766c`
- Samples per case: 3
- Cost: subject $0.0454, judge $0.0000

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| sentence | 67 | 201 | 0 | 201/201 | — | 0/0 | 0.79s / 1.03s | $0.00013 |
| escalation | 9 | 27 | 0 | 19/27 | — | 0/0 | 0.81s / 1.14s | $0.00075 |

## Worth a look (8)

- **escalation/want_chocolate** #2: I want to eat chocolate. → I really want to eat chocolate right now! → I really NEED to eat chocolate right now! → I want to eat chocolate!  
  rung 3 less insistent than rung 2 (3 < 9)
- **escalation/mom_hungry** #0: Mom, I am hungry. → Mom, I am really hungry right now! → Mom, I am really hungry! Can I eat something? → Mom, I am really hungry! Can I eat something right now?  
  rung 2 less insistent than rung 1 (3 < 5)
- **escalation/mom_hungry** #1: Mom, I am hungry. → Mom, I am really hungry right now! → Mom, I am really hungry right now! I need food! → Mom, I am really hungry! Can I eat?  
  rung 3 less insistent than rung 2 (3 < 8)
- **escalation/where_mom** #0: Where is Mom? → Where is Mom? I need her now! → Mom, where are you? I need you now! → Mom, where are you?  
  rung 3 less insistent than rung 2 (0 < 4); no escalation across the ladder (0 → 0)
- **escalation/where_mom** #1: Where is Mom? → Mom, where are you? → Mom, where are you? → Mom, where are you?  
  no escalation across the ladder (0 → 0)
- **escalation/where_mom** #2: Mom, where are you? → Mom, where are you? → Mom, where are you? → Mom, where are you?  
  no escalation across the ladder (0 → 0)
- **escalation/want_chocolate_IV** #1: I want to eat chocolate. → I really want to eat chocolate right now! → I really NEED to eat chocolate right now! → I want to eat chocolate!  
  rung 3 less insistent than rung 2 (3 < 9)
- **escalation/want_chocolate_IV** #2: I want to eat chocolate. → I really want to eat chocolate right now! → I really NEED to eat chocolate right now! → I want to eat chocolate!  
  rung 3 less insistent than rung 2 (3 < 9)
