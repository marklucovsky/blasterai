# Eval run 2026-10-21-1514-gpt-6.1-sol-low-topic-t8-sol-addpage

- Subject: `gpt-6.1-sol` (effort `low`)
- Judge: `gpt-6-astra` × 1
- Commit `d1d0f5c+dirty`, prompts `b98114c001`, rubrics `fc770a3add`
- Samples per case: 3
- Cost: subject $0.4018, judge $1.3081

| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |
|---|---|---|---|---|---|---|---|---|
| topic_words | 16 | 48 | 0 | 20/48 | child_fit 4.73, coverage 4.98, precision 4.52, ranking 4.69, related_core 4.65 | 4/48 | 12.89s / 16.77s | $0.00837 |

## Worth a look (30)

- **topic_words/ap_christmas_songs** #2: (29 tiles)  
  missing 'jingle_bells / jingle'
- **topic_words/ap_christmas_songs_bare** #2: (32 tiles)  
  missing 'jingle_bells / jingle'
- **topic_words/ap_bluey_characters** #0: (30 tiles)  
  related_core=2
- **topic_words/ap_bluey_characters** #1: (28 tiles)  
  related_core=2
- **topic_words/ap_bluey_characters_bare** #0: (29 tiles)  
  missing 'bandit'; missing 'chilli'; missing 'muffin / socks / coco / rusty / nana'
- **topic_words/ap_bluey_characters_bare** #1: (25 tiles)  
  missing 'bandit'; missing 'chilli'; missing 'muffin / socks / coco / rusty / nana'
- **topic_words/ap_bluey_characters_bare** #2: (25 tiles)  
  missing 'bandit'; missing 'chilli'; missing 'muffin / socks / coco / rusty / nana'
- **topic_words/ap_mcdonalds_desserts_bare** #0: (32 tiles)  
  missing 'mcflurry'; missing 'apple_pie / baked_apple_pie'; missing 'cone / ice_cream_cone / sundae / hot_fudge_sundae' (in the overflow)
- **topic_words/ap_mcdonalds_desserts_bare** #1: (32 tiles)  
  missing 'mcflurry'; missing 'apple_pie / baked_apple_pie'; missing 'cone / ice_cream_cone / sundae / hot_fudge_sundae' (in the overflow)
- **topic_words/ap_mcdonalds_desserts_bare** #2: (32 tiles)  
  missing 'mcflurry'; missing 'apple_pie / baked_apple_pie'; missing 'cone / ice_cream_cone / sundae / hot_fudge_sundae' (in the overflow)
- **topic_words/ap_yellowstone_animals_bare** #0: (32 tiles)  
  missing 'bison'; missing 'elk'; missing 'wolf / grizzly_bear / grizzly'; missing 'moose / pronghorn / bighorn_sheep / bald_eagle'
- **topic_words/ap_yellowstone_animals_bare** #1: (32 tiles)  
  missing 'bison'; missing 'elk'; missing 'wolf / grizzly_bear / grizzly'; missing 'moose / pronghorn / bighorn_sheep / bald_eagle'
- **topic_words/ap_yellowstone_animals_bare** #2: (32 tiles)  
  missing 'bison'; missing 'elk'; missing 'wolf / grizzly_bear / grizzly'; missing 'moose / pronghorn / bighorn_sheep / bald_eagle'
- **topic_words/ap_frozen_characters_bare** #0: (25 tiles)  
  missing 'elsa'; missing 'anna'; missing 'olaf'; missing 'sven'; missing 'kristoff'
- **topic_words/ap_frozen_characters_bare** #1: (30 tiles)  
  missing 'anna' (in the overflow); missing 'sven'; missing 'kristoff'
- **topic_words/ap_frozen_characters_bare** #2: (25 tiles)  
  missing 'elsa'; missing 'anna'; missing 'olaf'; missing 'sven'; missing 'kristoff'; related_core=1
- **topic_words/ap_disney_rides** #0: (32 tiles)  
  phrase tile(s): it’s_a_small_world, the_many_adventures_of_winnie_the_pooh; missing "space_mountain / big_thunder_mountain / splash_mountain / its_a_small_world / it's_a_small_world / small_world"
- **topic_words/ap_disney_rides** #1: (32 tiles)  
  phrase tile(s): it's_a_small_world, the_many_adventures_of_winnie_the_pooh; precision=3
- **topic_words/ap_disney_rides** #2: (32 tiles)  
  phrase tile(s): it's_a_small_world, seven_dwarfs_mine_train
- **topic_words/ap_disney_rides_bare** #0: (29 tiles)  
  missing 'dumbo'; missing 'teacups / tea_cups / mad_tea_party'; missing "space_mountain / big_thunder_mountain / splash_mountain / its_a_small_world / it's_a_small_world / small_world"
- **topic_words/ap_disney_rides_bare** #1: (32 tiles)  
  missing 'dumbo'; missing 'teacups / tea_cups / mad_tea_party'; missing "space_mountain / big_thunder_mountain / splash_mountain / its_a_small_world / it's_a_small_world / small_world"
- **topic_words/ap_disney_rides_bare** #2: (31 tiles)  
  missing 'dumbo'; missing 'teacups / tea_cups / mad_tea_party'; missing "space_mountain / big_thunder_mountain / splash_mountain / its_a_small_world / it's_a_small_world / small_world"
- **topic_words/ap_caterpillar_foods_bare** #0: (32 tiles)  
  missing 'pear'; missing 'plum'; missing 'pickle'; missing 'chocolate_cake / cake'
- **topic_words/ap_caterpillar_foods_bare** #1: (32 tiles)  
  missing 'pear'; missing 'plum'; missing 'pickle'; missing 'chocolate_cake / cake'
- **topic_words/ap_caterpillar_foods_bare** #2: (32 tiles)  
  missing 'pear'; missing 'plum'; missing 'pickle'; missing 'chocolate_cake / cake'
- **topic_words/ap_mario_powerups** #0: (30 tiles)  
  missing '1-up / 1-up_mushroom / one-up / 1up'
- **topic_words/ap_mario_powerups** #2: (32 tiles)  
  missing '1-up / 1-up_mushroom / one-up / 1up'
- **topic_words/ap_mario_powerups_bare** #0: (23 tiles)  
  missing 'fire_flower'; missing '1-up / 1-up_mushroom / one-up / 1up'
- **topic_words/ap_mario_powerups_bare** #1: (23 tiles)  
  missing 'fire_flower'; missing '1-up / 1-up_mushroom / one-up / 1up'
- **topic_words/ap_mario_powerups_bare** #2: (24 tiles)  
  missing 'fire_flower'; missing '1-up / 1-up_mushroom / one-up / 1up'
