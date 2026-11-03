import sys, os, json, re, time, urllib.request
sys.path.insert(0,'.')
from fs import api
ROOT='/Users/hridyaagrawal/Honey/anvil/foundry-ad/literal'
META='/private/tmp/claude-501/-Users-hridyaagrawal-Honey-anvil/9feff43d-fe9e-44bb-80f1-6716bbcf6984/scratchpad/work/meta'
os.makedirs(META,exist_ok=True)
def slug(n):
    n=re.sub(r'\.(wav|mp3|aif|aiff|flac|m4a|ogg)$','',n,flags=re.I)
    return re.sub(r'[^a-z0-9]+','-',n.lower()).strip('-')[:40]
def get(cat, ids):
    for i in ids:
        mp=f'{META}/{i}.json'
        try:
            if os.path.exists(mp): m=json.load(open(mp))
            else:
                m=api(f'sounds/{i}/',fields='id,name,license,username,duration,previews,url,description,tags,type,samplerate,channels,bitdepth,filesize,created,download')
                m['category']=cat; json.dump(m,open(mp,'w'),indent=1); time.sleep(1.0)
            lic=m['license']
            ok = 'zero' in lic or re.search(r'/by/(2\.5|3\.0|4\.0|2\.0)/',lic)
            if not ok: print('SKIP licence',i,lic); continue
            u=m['previews']['preview-hq-ogg']
            out=f"{ROOT}/audio/assets/{cat}/fs-{i}_{slug(m['name'])}.ogg"
            if os.path.exists(out) and os.path.getsize(out)>1000: print('have',i); continue
            r=urllib.request.Request(u,headers={'User-Agent':'literal-sourcing/1.0'})
            data=urllib.request.urlopen(r,timeout=60).read()
            open(out,'wb').write(data); print('ok',i,len(data),os.path.basename(out),flush=True)
        except Exception as e:
            print('ERR',i,e,flush=True)
        time.sleep(1.5)
if __name__=='__main__':
    cat=sys.argv[1]; get(cat,[int(x) for x in sys.argv[2:]])
