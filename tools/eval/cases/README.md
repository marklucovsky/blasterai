<!-- SPDX-License-Identifier: Apache-2.0 -->
# Eval cases

One file per surface. Each case:

```json
{"id": "she_pool", "group": "subject", "probe": "what this case is for",
 "input": { ... }, "expect": { ... }}
```

`id` is unique within its file; `--cases` matches substrings of it, `--group`
matches `group` exactly. `probe` is for people and the report — not scored.

## Inputs

| Surface | `input` |
|---|---|
| sentence | `stage` ("II-III" or "IV+"), `tiles` as `"value:class"`, optional `history` (earlier sentences), optional `refine` (`[original, instruction]`) |
| escalation | `stage`, `tiles`, `rungs` (total sentences, the first one calm) |
| scene_generate | `description` |
| scene_refine | `instruction`, `current` (keys, or `{"key", "displayName"}` for a proposed new word) |
| page_generate | `goal`, `page_name`, optional `scene_pages` (`[{"key", "tiles": [keys]}]`) and `home_page_key` |
| page_refine | `instruction`, `page_name`, `current`, optional `scene_pages`, `home_page_key` |
| tile_suggest | `goal` |
| moderation | `words` (one rubric call rates them all, as one word-add batch does in the app) |

Tile classes are what the app sends: the word's `wordClass` in
`vocabulary.json` (so `school` arrives as `school (social)` — a finding, not a
typo here), or the pack's class for a pack word.

Stage I is not a surface: single-word mode makes no API call. Nor is a single
tile at any stage: `SentenceEngine` speaks a lone tile as its word and a repeat
re-speaks it, so sentence and escalation cases need at least two tiles — the
runner refuses fewer.

## Expectations (Tier 1)

Keep them to what is clear-cut; quality is the judge's and the review's job.
A list inside a list means "any one of these".

Sentences: `must_include`, `must_not_include` (whole words, any case),
`must_match`, `must_not_match` (regex, any case), `question`, `negation`,
`subject` (that word must appear), `max_words`. Every sentence (not escalation) also gets the stage-wide length check in `scorers.length_issues`: at most 12 words at Stage II-III, at most two sentences at any stage.

Authoring: `must_include_keys`, `must_not_include_keys` (a plural/singular swap
and spaces-for-underscores count as a match), `min_tiles`, `max_tiles`,
`refused` (the topic must be declined with no tiles). Refines also fail when a
current tile disappears without being asked to.

Moderation: `ratings` (`{"word": "appropriate" | "questionable" |
"inappropriate"}`). Deliberately empty for now — the policy is set after the
baseline shows what the rubric does.
