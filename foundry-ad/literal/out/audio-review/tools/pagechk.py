import sys,os,re,json,time,html,subprocess
CERT='/Users/hridyaagrawal/Honey/earshot/.venv/lib/python3.12/site-packages/certifi/cacert.pem'
os.makedirs('pagelic',exist_ok=True)
for i in sys.argv[1:]:
    m=json.load(open(f'meta/{i}.json')); url=m['url']
    out=f'pagelic/{i}.json'
    if os.path.exists(out): continue
    r=subprocess.run(['curl','-sL','-m','40','-A','literal-sourcing/1.0 (licence check)','--cacert',CERT,url],capture_output=True,text=True)
    h=r.stdout
    t=re.search(r'<title>Freesound - (.*?) by (.*?)</title>',h,re.S)
    lic=re.search(r'title="Go to the full license text" href="([^"]+)"[^>]*>\s*([^<]+?)\s*<',h)
    dsc=re.search(r'<meta property="og:description" content="([^"]*)"',h)
    ok=bool(t and lic)
    rec=dict(id=i,ok=ok,page_title=html.unescape(t.group(1)).strip() if t else None,page_author=html.unescape(t.group(2)).strip() if t else None,
      licence_url=lic.group(1) if lic else None,licence_text=html.unescape(lic.group(2)).strip() if lic else None,
      page_url=url,seen=time.strftime('%Y-%m-%d'),bytes=len(h))
    json.dump(rec,open(out,'w'),indent=1); print(i,ok,rec['licence_text'],rec['page_author'],flush=True)
    time.sleep(1.5)
