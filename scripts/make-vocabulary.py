#!/usr/bin/env python3
"""Rebuild the unified vocabulary from an ECDICT CSV (Python standard library)."""
import argparse, csv, json, re
from pathlib import Path

BASIC = set('''kit burning talented buddy shrimp cartoon bug bonus locker pal trader follower making cowboy chat pupil fake crab organizer memo trillion cocktail affordable comic mattress lottery soy motorcycle buffalo nickname mustard cleaning relaxed pumpkin stereo olive homemade dolphin cinema coupon unpaid rectangle sailing grass grassy willow pickle villa fluffy stairway folding coconut zebra lollipop yogurt yoghurt popcorn jelly babysitter toothbrush toothpaste notebook suitcase boyfriend girlfriend dad mum mom grandma grandpa aunt uncle niece nephew panda penguin giraffe cucumber tomato potato onion garlic chicken pork beef bacon ham pizza sandwich hamburger spaghetti noodle noodles biscuit cookies cookie cake bread milk juice lemonade soda beer coffee tea candy chocolate toothbrush butterfly rainbow sunlight sunshine moonlight snowman snowball seaside inland upside downside indoor outdoor northwards southwards eastwards westwards someday anytime everyday anyhow downstairs upstairs airplane airport volleyball basketball football tennis soccer baseball jogging swimming shopping camping cramming reheating cleaner rider driver swimmer singer dancer runner happily slowly loudly loudly newborn teenage toddler babysitting billionaire millionaire kilo metre meter centimetre kilogram gram thermometer daylight bedtime eyesight haircut playground hometown internet email website online laptop keyboard mouse printer smartphone headphone earphone password username download upload'''.split())
ADVANCED_TAGS = {'gre', 'cet6', 'ielts', 'toefl'}
BASIC_TAGS = {'zk', 'gk', 'cet4'}

def number(row, key):
    return int(row.get(key) or 0)

def select(rows):
    words = {}
    for row in rows:
        word = row['word'].strip().lower()
        tags = set(row['tag'].split())
        if not tags.intersection(ADVANCED_TAGS): continue
        if tags.intersection(BASIC_TAGS) or number(row, 'oxford') > 0: continue
        if word in BASIC or not re.fullmatch(r'[a-z]+(?:-[a-z]+)?', word): continue
        if not row['translation'].strip(): continue
        if any(0 < number(row, k) <= 5000 for k in ['bnc', 'frq']): continue
        if re.search(r'(^|/)0:', row['exchange']): continue
        words[word] = dict(id=word, word=word, phonetic=row['phonetic'],
            meaning=row['translation'].replace('\\n', '\n'), example='', exampleTranslation='',
            frequency=number(row, 'frq') or number(row, 'bnc') or 999999)
    return [words[key] for key in sorted(words)]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv', type=Path)
    args = parser.parse_args()
    with args.csv.open(encoding='utf-8-sig', newline='') as f:
        words = select(csv.DictReader(f))
    destination = Path(__file__).resolve().parent.parent / 'Resources/advanced.json'
    destination.write_text(json.dumps(words, ensure_ascii=False, indent=2) + '\n')
    print(f'{len(words)} words -> {destination}')
