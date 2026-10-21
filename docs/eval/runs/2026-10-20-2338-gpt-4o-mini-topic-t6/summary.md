# Eval run 2026-10-20-2338-gpt-4o-mini-topic-t6

- Subject: `gpt-4o-mini`
- Judge: `gpt-6.1-sol` × 1
- Commit `d1d0f5c+dirty`, prompts `c9066f898f`, rubrics `8f550b6a15`
- Samples per case: 3
- Cost: subject $0.0566, judge $0.4312

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 34 | 102 | 0 | 43/102 | child_fit 3.53, coverage 2.90, precision 3.00, ranking 3.23, related_core 2.95 | 99/99 | 4.62s / 6.76s | $0.00055 |

## Worth a look (99)

- **topic_words/potty_training** #0: (28 tiles)  
  new word(s) with an unknown wordClass: done; coverage=3; precision=2; related_core=3; ranking=3; child_fit=3
- **topic_words/potty_training** #1: (28 tiles)  
  new word(s) with an unknown wordClass: done; coverage=3; precision=2; related_core=3
- **topic_words/potty_training** #2: (28 tiles)  
  new word(s) with an unknown wordClass: done; missing 'wash'; coverage=3; precision=2; related_core=3; ranking=2; child_fit=3
- **topic_words/dentist** #0: (27 tiles)  
  missing 'sit'; coverage=3; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/dentist** #1: (27 tiles)  
  missing 'sit'; missing 'scared / hurt'; coverage=3; precision=3; related_core=3; child_fit=3
- **topic_words/dentist** #2: (28 tiles)  
  missing 'sit'; coverage=3; precision=3; related_core=3; child_fit=3
- **topic_words/farm_trip** #0: (30 tiles)  
  missing 'farmer'; coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/farm_trip** #1: (28 tiles)  
  missing 'farmer'; coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/farm_trip** #2: (29 tiles)  
  missing 'farmer'; coverage=3; precision=3; related_core=3
- **topic_words/birthday_party** #0: (27 tiles)  
  missing 'open'; coverage=3; precision=3; related_core=3
- **topic_words/birthday_party** #1: (27 tiles)  
  missing 'open'; coverage=3; precision=3; related_core=3
- **topic_words/birthday_party** #2: (28 tiles)  
  missing 'open'; coverage=3; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/swimming** #0: (29 tiles)  
  missing 'scared / cold'; coverage=3; precision=3; related_core=3
- **topic_words/swimming** #1: (26 tiles)  
  missing 'wet'; missing 'scared / cold'; coverage=3; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/swimming** #2: (28 tiles)  
  missing 'scared / cold'; coverage=3; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/hospital_stay** #0: (28 tiles)  
  missing 'hurt'; missing 'mom / dad / family' (in the overflow); coverage=3; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/hospital_stay** #1: (29 tiles)  
  missing 'hurt'; missing 'mom / dad / family'; coverage=2; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/hospital_stay** #2: (28 tiles)  
  missing 'hurt'; coverage=3; precision=3; related_core=3; child_fit=3
- **topic_words/church** #0: (28 tiles)  
  missing 'quiet'; coverage=3; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/church** #1: (29 tiles)  
  missing 'quiet'; coverage=3; precision=3; related_core=3; child_fit=3
- **topic_words/church** #2: (27 tiles)  
  missing 'quiet'; coverage=2; precision=3; related_core=3; child_fit=3
- **topic_words/morning_circle** #0: (29 tiles)  
  coverage=2; precision=3; related_core=3; ranking=2
- **topic_words/morning_circle** #1: (31 tiles)  
  missing 'teacher' (in the overflow); coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/morning_circle** #2: (29 tiles)  
  coverage=2; precision=3; related_core=3; ranking=3
- **topic_words/grocery_store** #0: (30 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/grocery_store** #1: (27 tiles)  
  coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/grocery_store** #2: (28 tiles)  
  ranking=3
- **topic_words/bedtime** #0: (28 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/bedtime** #1: (27 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/bedtime** #2: (27 tiles)  
  coverage=3; precision=3; child_fit=3
- **topic_words/sensory_break** #0: (28 tiles)  
  coverage=3; precision=3; related_core=3
- **topic_words/sensory_break** #1: (18 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/sensory_break** #2: (27 tiles)  
  coverage=3; precision=3; ranking=3
- **topic_words/zoo_terse** #0: (30 tiles)  
  missing 'zookeeper'; coverage=3; precision=3; ranking=3
- **topic_words/zoo_terse** #1: (30 tiles)  
  missing 'zookeeper'; coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/zoo_terse** #2: (30 tiles)  
  missing 'zookeeper'; coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/pancakes_long** #0: (29 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2; child_fit=3
- **topic_words/pancakes_long** #1: (28 tiles)  
  coverage=3; precision=2; related_core=3; ranking=2; child_fit=3
- **topic_words/pancakes_long** #2: (29 tiles)  
  coverage=3; precision=3; related_core=3; child_fit=3
- **topic_words/holidays** #0: (29 tiles)  
  missing 'give'; missing 'open'; coverage=3; related_core=3
- **topic_words/holidays** #1: (29 tiles)  
  missing 'give'; missing 'open'; coverage=3; related_core=3
- **topic_words/holidays** #2: (29 tiles)  
  missing 'give'; missing 'open'; coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/doctor_visit** #0: (27 tiles)  
  missing 'wait'; missing 'sit / lie_down'; coverage=3; precision=3; related_core=3
- **topic_words/doctor_visit** #1: (28 tiles)  
  missing 'sit / lie_down'; missing 'scared / hurt'; coverage=3; precision=3; related_core=3; ranking=3
- **topic_words/doctor_visit** #2: (27 tiles)  
  missing 'sit / lie_down'; coverage=3; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/restaurant** #0: (28 tiles)  
  coverage=3; precision=3; related_core=3
- **topic_words/restaurant** #1: (27 tiles)  
  coverage=3; precision=3; related_core=3
- **topic_words/restaurant** #2: (27 tiles)  
  coverage=3; precision=3; related_core=3
- **topic_words/bible_stories** #0: (26 tiles)  
  coverage=2; precision=3; related_core=3; ranking=3; child_fit=3
- **topic_words/bible_stories** #1: (27 tiles)  
  coverage=3; related_core=3; child_fit=3
- **topic_words/bible_stories** #2: (28 tiles)  
  coverage=2; precision=3; related_core=3; child_fit=2
- **topic_words/favorite_show** #0: (27 tiles)  
  missing 'watch'; coverage=2; precision=2; related_core=3; child_fit=3
- **topic_words/favorite_show** #1: (28 tiles)  
  coverage=2; precision=2; related_core=3; child_fit=3
- **topic_words/favorite_show** #2: (28 tiles)  
  coverage=2; precision=2; related_core=3; child_fit=3
- **topic_words/snack_time** #0: (30 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/snack_time** #1: (26 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/snack_time** #2: (28 tiles)  
  coverage=3; precision=3; related_core=3
- **topic_words/movie** #0: (28 tiles)  
  coverage=3; precision=3; related_core=3; ranking=2
- **topic_words/movie** #1: (29 tiles)  
  coverage=3; precision=3; related_core=3
- **topic_words/movie** #2: (29 tiles)  
  coverage=2; precision=3; related_core=2; ranking=1; child_fit=3
