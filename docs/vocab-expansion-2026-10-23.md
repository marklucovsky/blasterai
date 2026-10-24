# Growing BlasterAI 60 — verb links and folders (draft for Brandi, 2026-10-23)

Brandi's read after our call: the vocabulary is still too small for people to
take it seriously, or to see that the board grows with the child. She suggested
two surgical changes, both used by Avaz:

1. **Verb links.** Do for more home words what we already do for *eat* and
   *drink*: the tile speaks its word **and** opens a page of what usually
   follows it.
2. **Folders on crowded pages.** Instead of a long scrolling page, each one
   keeps its most useful words up front, plus silent folder tiles for less
   common words ("House places", "School places"…).

Every target is a **fixed page**, chosen once by us and the SLP, never
generated from what the child pressed. That keeps motor planning stable: the
same word is always in the same place.

A third Avaz idea, the verb-form bubble (*come* → came / comes / coming / will
come), is parked for later behind a "grammar" setting.

**How to read this draft:** words marked **\*** are new to BlasterAI, and the
number after one is the age in months at which half of children say it. Mark
anything up: cut it, move it, rename a folder.

## Which words to add: the CDI, through Wordbank

The MacArthur-Bates CDI forms are copyrighted, so we don't copy them. Wordbank
(Stanford, CC BY 4.0) publishes the data collected **with** them, from
thousands of American English Words & Sentences forms. That includes each
word's age of acquisition: the age at which half of children say it. We compare
our vocabulary against that data (`tools/wordbank_coverage.py`).

| Age most children say it by | BlasterAI has |
|---|---|
| 18 months | 8 of 12 |
| 24 months | 119 of 156 (76%) |
| 30 months | 211 of 384 (54%) |
| later | 48 of 128 |

**Where the gap is:** our core words already match the CDI well. Pronouns
(21/25), question words (7/7), time words (12/12), locations (18/26) and verbs
(74/103) are mostly covered. What's missing is concrete nouns:

| CDI category | Have |
|---|---|
| Household | 15 / 50 |
| Animals | 13 / 43 |
| Furniture & rooms | 11 / 33 |
| Outside | 11 / 31 |
| Clothing | 8 / 28 |
| Sounds | 2 / 12 |

These are the words a folder holds well, so the CDI supports Brandi's
structure: keep core words on Home, and grow the nouns behind folders.

This is different from what we chose not to copy from Vocal Flair
(`vocabulary-gaps-2026-10-19.md`). Their size comes from adult domain folders:
jobs, news, church, technology. These folders are the everyday words a
two-year-old says.

## 1. Verb links from Home

Today *eat*, *drink* and *play* on Home speak their word and open a page.
Proposed additions:

| Home word | Opens | Notes |
|---|---|---|
| **I** | new **"I" page** | am, want, need, like, love, feel, see, have, can, can't, don't, will, was, did, think, know, go, help, gonna\*29, wanna, have to\*31, let me\*28 |
| **go** | **Places** | the restructured Places below |
| **come** | **Places** | Avaz links *go* and *come* to the same Places page |
| **feel** | **Feelings** | Avaz has *feel* on Home as an audible link; ours is on Actions |
| want | Things? | *Brandi:* would "want" open Things, Food, or nothing? |
| watch | new **Watch** page? | TV, movie, iPad, show\*, video\*, cartoon\* |

Brandi named *I* and *go*; *come* and *feel* are what Avaz does. *want* and *watch* are questions for her. Every link keeps
its word: tapping *I* still puts "I" in the sentence.

## 2. Folders on crowded pages

**Layout rule (to decide):** folder tiles take a fixed position on every page
that has them, so each page fits on one screen, with no paging. Avaz puts them
in the **right-hand one or two columns** (Food, Places), sometimes the left
column too (Things), as white folder-tab tiles. Our Home has its link row on top.

**Colour.** In Avaz, an audible link keeps its word's colour (a green *go*, with
a small arrow in the corner); only folders are white. Ours paints *eat*, *drink*
and *play* blue under the default "Always the Link Color" setting. Audible links
should keep their Fitzgerald colour by default, set separately from folders.

### Places (48 words today), opened by *go*

**Up front:** home, school, park, playground, store, restaurant, doctor,
outside, inside\*, bathroom, bedroom, kitchen, church, library, pool, beach,
zoo, farm, therapy, speech, grandma's house\*, friend's house\*

| Folder | Words |
|---|---|
| House places | bedroom, kitchen, bathroom, living room, dining room, backyard, closet, laundry, garage\*28, basement\*36, stairs\*26, porch\* |
| School places | class, playground, library, gym\*, cafeteria\*, office\*, speech, therapy |
| Fun places | park, zoo, beach, pool, lake, ocean, farm, camp, movie, bowling alley, party\*27, picnic\*30, circus\*34 |
| Out & about | store, grocery store, mall, doctor, dentist\*, hospital\*, church, airport, gas station\* |
| Places to eat | restaurant, cafeteria\*, pizza place\*, ice cream shop\* |

**Moves off Places:** slide and swing → Play; bus, car, train, bicycle,
airplane and boat → Vehicles; door and window → House things; lunch → Food.

### Actions (121 words, 3 screens)

**Up front (~40):** need, have, eat→, drink→, play→, want, get, give, take,
go, come, stop, help, like, do, make, put, open, close, look, see, watch,
find, wait, finish, try, read, write, draw, work, am, are, was, hug, sit,
stand, walk, run, jump, sleep

| Folder | Words |
|---|---|
| Moving | walk, run, jump, climb, dance, ride, drive, fly, fall, push, pull, turn, swim, move, hurry\*29, chase\*29, carry\*27, hold\*27, drop\*28, bump\*28 |
| Taking care | wash, wash hands, wash hair, bathe, shower, brush, brush teeth, dry, wear, dress up, clean, nap, wipe\*27, sweep\*28, wake\*28, feed\*28 |
| Talking | tell, listen, talk, say, ask, answer, speak, call, email, meet, show, knock\*27 |
| Thinking & feeling | know, think, learn, remember, forget, understand, feel, love, hate, hope, wish, guess, pray, cry, hurt, smile\*28 |
| Playing | catch, throw, kick, build, hide, share, blow, bowl, color, paint, sing, tickle\*25, splash\*27, pretend\*32 |
| Eating & cooking | bite, chew, cut, pour, cook, taste\*29, lick\*29, spill\*28 |
| My senses | look, see, hear, smell, taste\*29, touch\*27 |

### Describe (122 words, 3 screens)

**Up front (~40):** big, little, good, bad, hot, cold, loud, quiet, fast,
slow, new, old, clean, dirty, wet, dry, full, empty, easy, hard, soft, yummy,
yucky, fun, boring, nice, mean, funny, pretty, broken, same, different, more,
all done, okay, right, wrong, open, closed, sleepy\*27

| Folder | Words |
|---|---|
| Feelings | the existing Feelings page, plus Avaz's intensifiers next to the feelings: very, so, too, a little, kind of\*, extremely\* |
| Colors & shapes | the existing page |
| Where | top, bottom, front, behind, over, under, near, far, left, right, middle, between, around, through, away, back, there, together, apart, on top of\*30, next to\*32 |
| When | the existing Time page (now, later, soon, first, next, last, today, always…) |
| How much | more, many, few, one, a lot\*30, another\*30, too\*27, better, best, worse, worst |
| How it feels | hot, cold, wet, dry, soft, hard, heavy, light, sticky, sharp, smelly, stinky, gentle\*29, stuck\*27 |

### Food (59 words, one full screen), opened by *eat*

**Up front (~20):** hungry, more, all done, yummy, yucky, snack, apple,
banana, cheese, crackers, chips, cookie, pizza, sandwich, nuggets, fries,
yogurt, cereal, bread\*23, ice cream\*23

| Folder | Words |
|---|---|
| Breakfast | cereal, oatmeal, pancakes, eggs, toast, syrup, yogurt, bread\*23, muffin\*27, Cheerios\*25, donut\*28, butter\*27 |
| Lunch & dinner | sandwich, pizza, hamburger, hot dog, nuggets, macaroni, soup, salad, noodles\*26, spaghetti\*26, meat\*28 |
| Fruit | apple, banana, blueberries, cherry, grapes, orange, pear, strawberry, lemon, raisin\*26, melon\*30 |
| Veggies | broccoli, carrot, corn, cucumber, green beans, lettuce, potato, tomato, pepper, peas\*26, pickle\*28, pumpkin\*27 |
| Snacks & treats | chips, crackers, goldfish cracker, graham cracker, pretzel, popcorn, fruit snack, cookie, chocolate, pudding, popsicle, candy\*24, cake\*23, ice cream\*23, lollipop\*29, gum\*30 |

### Groups, where most of the new words go

The existing Groups folders (Animals, Clothes, Things) are small today: 10, 7
and 11 words. Most of the CDI gap belongs here.

| Folder | Add |
|---|---|
| Animals (10 → ~30) | bear\*21, bee\*22, bunny\*22, monkey\*22, bug\*23, elephant\*23, frog\*23, butterfly\*24, lion\*24, turtle\*24, giraffe\*25, mouse\*25, owl\*25, tiger\*25, squirrel\*26, zebra\*26, penguin\*27, alligator\*27 |
| Clothes (7 → ~20) | diaper\*21, boots\*23, button\*24, jacket\*25, bib\*26, zipper\*26, dress\*27, sweater\*27, gloves\*28, mittens\*29, jeans\*29, underpants\*29 |
| House things (new; Things splits) | bottle\*21, keys\*22, telephone\*22, chair\*22, box\*24, pillow\*24, soap\*24, bathtub\*24, table\*25, clock\*25, glasses\*25, towel\*25, picture\*25, couch\*26, napkin\*26, tissue\*26, trash\*27, sink\*27, refrigerator\*27, crib\*27, door, window |
| Outside (new) | tree\*21, flower\*22, moon\*22, rock\*24, grass\*25, sky\*25, stick\*26, street\*27, shovel\*27, snowman\*28 |
| Toys (Play) | balloon\*19, teddy bear\*25, present\*27, chalk\*29 |
| Body | toe\*22, belly button\*22, cheek\*25, chin\*25, tongue\*25, lips\*27, shoulder\*28 |
| Sounds (new?) | ouch\*18, uh oh, shh\*19, peekaboo\*20, meow\*17, vroom\*18, choo choo\*20 |

**Things, the Avaz way:** its Things page is ~25 common objects plus folders:
Appliances, Gadgets, Art & stationery, Tools, Kitchen items, Personal care,
Around the house, Toys, Books, Sports, Sensory things, My stuff. Its Toys page
carries sensory toys (kinetic sand, slime, squeeze balls, fidgets), which
matter for our kids and are not on the CDI. Brand names (Lego, Barbie, Jenga)
draw fine with gpt-image-2; named characters often don't.

**Phrase tiles** (Avaz's pink "I want to eat", "can I have some more?") are a
separate discussion, not part of this draft.

**About 130 new words.** Each needs art (gpt-image-2, all five styles) and a
part of speech. That's real cost, but bounded.

## What Avaz does: its folder tree

Mark screenshotted 76 Avaz screens on 2026-10-23. This records structure
(folder names, word counts per screen), not their word lists. Not captured:
the subtrees under Things, Food, Body Parts, Transport and Topics.

**Scale.** The captured screens alone hold **1,619 distinct words**; we have
363 of them. With the missing subtrees Avaz is likely 2,500+, against our 622.
That is Brandi's "too small".

**Shape.**

- **Home:** ~45 core words, 5 folders (Things, Body Parts, Food, Transport,
  Topics), and audible links on go, come, eat, drink and feel.
- **A bottom bar on every screen:** Quick, People, Questions, Actions,
  Feelings, Time, Short Words, Places, Describe, Special Interest.
- **A category page:** 30–45 words plus 6–8 folders, on one screen.
- **A subfolder:** 20–50 words on one screen. Only long lists page:
  Professions, Numbers, Position, Self Regulation.
- **Depth:** two levels below Home is the rule. A few go deeper: Grooming →
  Personal hygiene, Time → Special days → Birthday / Wedding day / Halloween,
  Geography → US states.
- **Describe** is the busiest category page: 44 adjectives plus 10 folders,
  and it still pages.

| Category | Avaz folders |
|---|---|
| Actions | Daily activities, Doing, Tell, Go, Sense, Cook and eat, Body, Think |
| Describe | Quality, Opinions, Appearance, Sense, Size, Shapes, Numbers, Color, Weather, Quantity |
| People | My family, My friends, School people, Other people, Professions, Pronouns |
| Feelings | Happy, Anxious, Angry, Sad, Hard feelings, Unwell, Self regulation |
| Time | Clock time, Date, Days of the week, Months, Special days (Birthday, Wedding day, Events, Vacation, Easter, Thanksgiving, Halloween, Christmas), Schedule, Weather |
| Places | House, School, Position, Public, Fun, Places to eat, Stores, Geography |
| Quick | Me me me, My gestalts, Manners, My supports, Respond, Explain & repair, Social, News |

**What this means for the draft:**

- **Actions:** our seven folders above land almost exactly on Avaz's eight,
  arrived at independently. That's good evidence the split is natural.
- **Describe:** adopt their Size, Sense, Opinions and Quantity split. Ours
  lumped them together.
- **People and Time:** split them the same way. People is 28 words today;
  Time already has days and the like.
- **Phrases are a separate discussion** (Mark, 2026-10-23). Avaz's Quick,
  Self regulation and My gestalts pages are phrase tiles. That's out of scope
  for this draft.
- **Not adopting:**
  - gendered grooming pages (Girl / Boy);
  - static holiday folders, since a holiday is an AI scene for us;
  - Geography's countries and states;
  - celebrity and politician folders.

## Questions for Brandi

1. Folder position on leaf pages: top row, like our Home, or the right-hand column, like Avaz?
2. The "I" page: right words, right order?
3. *want*, *watch*, *feel*: link them, and to what?
4. Up-front words on each page: is that the top 20–40 she'd want?
5. A Sounds folder: animal and vehicle sounds are among the earliest CDI words.
   Is that useful for our kids, or noise?
6. Anything Avaz has in folders that the CDI misses for older or school-age
   children?

*Wordbank: Frank, Braginsky, Yurovsky & Marchman (2017), Journal of Child
Language 44(3), 677–694; data CC BY 4.0, Redivis datapages.wordbank v3.4.*
