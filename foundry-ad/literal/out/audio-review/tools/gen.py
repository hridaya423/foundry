import sys, os, json, glob, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spec
from earshot import api

ROOT = '/Users/hridyaagrawal/Honey/anvil/foundry-ad/literal'
W = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)

AN = {}
for c in ('tiles', 'keys', 'fx', 'music'):
    p = f'out/audio-review/{c}_a.json'
    if os.path.exists(p):
        for x in json.load(open(p)):
            AN[os.path.basename(x['file'])] = x

KEYS = ('duration', 'codec', 'kbps', 'src_rate', 'channels', 'peak_dbfs', 'lufs', 'noise_floor_dbfs', 'clipped_samples',
        'attack_at', 'centroid_hz', 'rolloff95_hz')


def an_of(fn):
    x = AN[os.path.basename(fn)]
    d = {k: x.get(k) for k in KEYS}
    d['onsets'] = [round(o, 3) for o in (x.get('onsets') or [])[:12]]
    return d


def lic_fields(pl):
    t = pl['licence_text']
    u = pl['licence_url'].replace('http://', 'https://')
    if 'Creative Commons 0' in t:
        return 'CC0 1.0', u
    m = re.search(r'Attribution (\d\.\d)', t)
    v = m.group(1)
    return f'CC BY {v}', f'https://creativecommons.org/licenses/by/{v}/'


def mt(f, need, a, b):
    q, alts = spec.Q[need.split('+')[0]]
    r = api.match(f, q, alts=alts, start=a, end=b)
    return {'query': q, 'z': round(r['z'], 2), 'verdict': r['verdict'], 'p_vs_alts': r.get('p_vs_alts'), 'start': a, 'end': b}


def rl(f, a, b):
    r = api.realness(f, start=a, end=b)
    return {'p_real': r['p_real'], 'verdict': r['verdict'], 'start': a, 'end': b}


out = {}
summary = {}
for e in spec.E:
    cat = e['cat']
    m = json.load(open(f"{W}/meta/{e['id']}.json"))
    pl = json.load(open(f"{W}/pagelic/{e['id']}.json"))
    assert pl['ok'], e['id']
    f = glob.glob(f"audio/assets/{cat}/fs-{e['id']}_*")[0]
    lic, lic_url = lic_fields(pl)
    a, b = e['seg']
    seg_match = mt(f, e['need'], a, b)
    seg_real = rl(f, a, b)
    trims = {}
    for lab, (x, y) in e.get('trims', {}).items():
        try:
            tm = mt(f, e['need'], x, y)
            tr = rl(f, x, y)
            trims[lab] = {'range': [x, y], 'match_z': tm['z'], 'match': tm['verdict'], 'p_real': tr['p_real'], 'realness': tr['verdict']}
        except Exception as ex:
            trims[lab] = {'range': [x, y], 'error': str(ex)[:80]}
    ent = {
        'id': f"fs-{e['id']}", 'category': cat, 'file': f, 'title': pl['page_title'], 'author': pl['page_author'],
        'source': 'freesound', 'page_url': pl['page_url'], 'download_url': m['previews']['preview-hq-ogg'],
        'license': lic, 'license_url': lic_url,
        'attribution': None if lic.startswith('CC0') else f"\"{pl['page_title']}\" by {pl['page_author']} ({pl['page_url']}), licensed under {lic} ({lic_url})",
        'need': e['need'], 'rank': e['rank'], 'best_segment': [a, b], 'notes': e['notes'],
        'licence_seen': {'text': pl['licence_text'], 'url': pl['licence_url'], 'page': pl['page_url'], 'read_on': pl['seen'], 'page_author': pl['page_author'], 'page_title': pl['page_title']},
        'analysis': an_of(f),
        'earshot': {'realness': seg_real['p_real'], 'realness_verdict': seg_real['verdict'], 'realness_trim': [a, b],
                    'match': {'query': seg_match['query'], 'z': seg_match['z'], 'verdict': seg_match['verdict'], 'p_vs_alts': seg_match['p_vs_alts']},
                    'trims': trims},
    }
    out.setdefault(cat, []).append(ent)
    print(cat, e['need'], e['rank'], ent['id'], 'real', seg_real['p_real'], seg_real['verdict'], '| match z', seg_match['z'], seg_match['verdict'], flush=True)

for md in spec.MUSIC:
    f = f"audio/assets/music/{md['id']}.mp3"
    q, alts = spec.Q['music']
    r = api.match(f, q, alts=alts, start=0.0, end=60.0)
    rr = api.realness(f, start=0.0, end=60.0)
    x = AN[os.path.basename(f)]
    ent = {
        'id': md['id'], 'category': 'music', 'file': f, 'title': md['title'], 'author': md['author'], 'source': 'mixkit',
        'page_url': md['list_url'],
        'download_url': f"https://assets.mixkit.co/music/{md['num']}/{md['num']}.mp3",
        'license': 'Mixkit Stock Music Free License', 'license_url': 'https://mixkit.co/license/#musicFree',
        'attribution': None, 'need': 'music', 'rank': md['rank'], 'best_segment': md['seg'], 'notes': md['notes'],
        'licence_seen': {'text': 'Mixkit Stock Music Free License (listed on the page as free: "Assets under the Mixkit Free License can be used in both commercial and non-commercial projects", mixkit.co home)',
                         'url': 'https://mixkit.co/license/', 'page': md['list_url'], 'read_on': '2026-11-01',
                         'caveat': 'The licence text itself is loaded in a script-driven modal; the page text fetched without a browser only lists the licence names. NOT read in full: confirm the Stock Music Free License modal at https://mixkit.co/license/ before the film ships; never register the film with Content ID.'},
        'analysis': {**an_of(f), 'bpm_grid_fit': md['bpm'], 'first_downbeat_s': md['off'], 'bar_s': round(240 / md['bpm'], 3), 'tempo_librosa': x.get('tempo'), 'key_librosa': (x.get('key') or [{}])[0].get('key')},
        'earshot': {'realness': rr['p_real'], 'realness_verdict': rr['verdict'], 'realness_trim': [0.0, 60.0],
                    'match': {'query': q, 'z': round(r['z'], 2), 'verdict': r['verdict'], 'p_vs_alts': r.get('p_vs_alts'), 'window': [0.0, 60.0]}},
    }
    out.setdefault('music', []).append(ent)
    print('music', md['id'], 'real', rr['p_real'], rr['verdict'], '| match z', round(r['z'], 2), r['verdict'], flush=True)

os.makedirs('audio/assets/manifests', exist_ok=True)
for cat, lst in out.items():
    lst.sort(key=lambda z: (z['need'], z['rank']))
    json.dump(lst, open(f'audio/assets/manifests/{cat}.json', 'w'), indent=1, ensure_ascii=False)
    print('wrote', cat, len(lst))
