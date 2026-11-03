import sys, os, json, urllib.parse, urllib.request, time, subprocess
KEY = subprocess.run([os.path.expanduser('~/.local/bin/envsync'),'get','NEXT_PUBLIC_FREESOUND_API_KEY'],capture_output=True,text=True).stdout.strip()
def api(path, **p):
    p['token']=KEY
    p={k:v for k,v in p.items() if v not in ('',None)}
    u='https://freesound.org/apiv2/'+path+'?'+urllib.parse.urlencode(p)
    err=None
    for i in range(3):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(u,headers={'User-Agent':'literal-sourcing/1.0'}),timeout=40))
        except urllib.error.HTTPError as e:
            if e.code==400: raise
            err=e; time.sleep(3)
        except Exception as e:
            err=e; time.sleep(2)
    raise err
LIC=['license:"Creative Commons 0"','license:"Attribution"']
def short(l):
    import re
    if 'zero' in l: return 'CC0'
    m=re.search(r'licenses/([a-z\-]+)/([0-9.]+)',l)
    return ('CC '+m.group(1)+' '+m.group(2)) if m else l[-20:]
def search(q, extra='', n=12, sort='score', seen=None):
    seen = seen if seen is not None else set()
    for lf in LIC:
        flt=(lf+' '+extra).strip()
        try:
            r=api('search/text/',query=q,filter=flt,page_size=n,sort=sort,fields='id,name,license,username,duration,previews,url,avg_rating,num_downloads')
        except Exception as e:
            print('ERR',q,flt,e); continue
        for x in r['results']:
            if x['id'] in seen: continue
            seen.add(x['id'])
            print(f"{x['id']:>8} {x['duration']:7.1f}s {short(x['license']):10.10} dl={x['num_downloads']:<6} r={x['avg_rating']:.1f} {x['username'][:14]:14} {x['name'][:58]}")
        time.sleep(0.6)
if __name__=='__main__':
    extra=sys.argv[1]
    for q in sys.argv[2:]:
        print('##',q,'|',extra); search(q,extra)
