// Molten renderer: scene pass (grade + heat + flow + crust) -> two-level bloom -> halation, shoulder, grain.
// Drawn only from composition time; no requestAnimationFrame.
(function () {
  const W = 1920, H = 1080;
  const canvas = document.getElementById("gl");
  canvas.width = W; canvas.height = H;
  const gl = canvas.getContext("webgl2", { preserveDrawingBuffer: true, antialias: false, premultipliedAlpha: false, alpha: false });
  const halfFloat = !!gl.getExtension("EXT_color_buffer_float");
  gl.getExtension("OES_texture_float_linear");

  const VS = `#version 300 es
  in vec2 a; out vec2 vUv;
  void main(){ vUv = a*0.5+0.5; gl_Position = vec4(a,0.,1.); }`;

  const COMMON = `#version 300 es
  precision highp float;
  in vec2 vUv; out vec4 fragColor;
  float h21(vec2 p){ p = fract(p*vec2(123.34,456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
  float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.-2.*f);
    return mix(mix(h21(i),h21(i+vec2(1,0)),u.x), mix(h21(i+vec2(0,1)),h21(i+vec2(1,1)),u.x), u.y); }
  float fbm(vec2 p){ float s=0., a=.5; for(int i=0;i<5;i++){ s+=a*vnoise(p); p=p*2.03+17.1; a*=.5; } return s; }
  vec3 body(float T){
    T = max(T, 0.);
    vec3 c = vec3(0.);
    c = mix(c, vec3(0.30,0.015,0.0), smoothstep(0.0,0.25,T));
    c = mix(c, vec3(1.10,0.16,0.01), smoothstep(0.2,0.5,T));
    c = mix(c, vec3(1.9,0.62,0.08), smoothstep(0.45,0.8,T));
    c = mix(c, vec3(2.8,1.7,0.55), smoothstep(0.75,1.1,T));
    c = mix(c, vec3(3.6,3.2,2.6), smoothstep(1.05,1.5,T));
    return c;
  }
  uniform vec2 uRes;
  // ---------------------------------------------------------------- lava
  // fld: liquid field (blurred mask), fuv: flow-advected coords, temp: 0 cold .. 1 fresh
  vec3 lava(float fld, vec2 fuv, float temp, out float bodyM){
    bodyM = smoothstep(0.30, 0.40, fld);
    float core = smoothstep(0.40, 0.92, fld);
    float n = fbm(fuv);
    float w = fbm(fuv*vec2(0.6,0.35) + vec2(n*1.7, n*0.9) + 4.3);   // domain-warped striations
    float T = temp*(0.50 + 0.55*core) + (w - 0.5)*0.55*temp + 0.12*core;
    T *= mix(0.7, 1.0, core);                                        // rims run cooler
    float slag = smoothstep(0.43, 0.30, w)*(1.0 - 0.75*temp);         // floating crust
    vec3 c = body(T);
    c = mix(c, body(T*0.45)*0.6 + vec3(0.03,0.02,0.015), slag*0.85);
    float h = fld + w*0.18;
    vec2 g = vec2(dFdx(h), dFdy(h))*uRes.y*0.18;
    vec3 nrm = normalize(vec3(-g, 1.0));
    float sp = pow(max(dot(reflect(normalize(vec3(-0.35,-0.6,-1.)), nrm), vec3(0,0,1)), 0.), 22.0);
    c += body(T + 0.6)*sp*0.55*(1.0 - slag);
    return c;
  }

`;

  const SCENE = COMMON + `
  uniform sampler2D uScene, uEdge, uMetal;
  uniform float uT, uHeat, uFlow, uPinch, uTilt, uSeed, uZoom, uLumHeat, uEmber, uMetalOn, uSat, uRaw, uIsolate, uFlowSpd, uContrast, uAmberS, uHeatMask;
  uniform vec2 uPan;
  // cast
  uniform sampler2D uLogo;
  uniform float uCast, uCastT, uPlate, uPol0, uPol1, uFlash, uIron, uSweep, uCastFade, uTau;
  uniform vec4 uImp;      // impacts (screen fractions): x1, y1, x2, y2
  uniform vec4 uStream;   // per stream: top y (fraction, 0 = frame top) s1, s2; widths px w1, w2
  uniform vec2 uImpT;     // contact times (cast seconds)
  vec2 voro(vec2 p){
    vec2 i=floor(p), f=fract(p); float d1=8., d2=8.;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++){
      vec2 g=vec2(x,y); vec2 r=g+vec2(h21(i+g), h21(i+g+3.7))-f; float d=dot(r,r);
      if(d<d1){ d2=d1; d1=d; } else if(d<d2) d2=d; }
    return vec2(sqrt(d1), sqrt(d2)-sqrt(d1));
  }
  vec3 grade(vec3 c){
    c = clamp((c - 0.5)*uContrast + 0.5, 0., 1.);
    float l = dot(c, vec3(.2126,.7152,.0722));
    c = mix(vec3(l), c, uSat);
    c = clamp((c - 0.06)/0.86, 0., 1.);
    c = c*c*(3.0-2.0*c)*0.85 + c*0.15;
    vec3 o = mix(vec3(0.0,0.004,0.008), vec3(1.0,0.985,0.95), c);
    // amber phosphor: brightness only, burnt warm (pictures in the tube; never the metal)
    float pl = dot(o, vec3(0.3, 0.55, 0.15));
    vec3 amber = vec3(1.0, 0.60, 0.24)*pow(pl, 0.92) + vec3(0.0, 0.22, 0.36)*pow(pl, 2.6);
    return mix(o, amber, uAmberS);
  }
  float lumAt(vec2 q, float lod){ return dot(textureLod(uScene, q, lod).rgb, vec3(.2126,.7152,.0722)); }

  // ---------------------------------------------------------------- cast: streams fill the wordmark mould
  vec3 castColor(vec2 s){                           // s: screen fraction, y down
    float asp = uRes.x/uRes.y;
    vec2 q = 0.5 + (s - 0.5)/uZoom;                 // mould coords
    vec4 L = texture(uLogo, q);
    float mask = L.r, sil = L.g, polN = L.b;
    vec2 qp = q*vec2(asp, 1.0);
    // mould plate: cast-iron sand, engraved cavities with a lit rim
    float grain = fbm(q*vec2(asp,1.)*180.0)*0.5 + fbm(q*vec2(asp,1.)*40.0)*0.5;
    vec3 plate = vec3(0.085,0.078,0.072)*(0.7 + 0.6*grain);
    vec2 mg = vec2(dFdx(mask), dFdy(mask));
    float rim = clamp(dot(mg*uRes.y*0.5, vec2(-0.6,-0.8)), 0., 1.);
    plate = mix(plate, vec3(0.018,0.016,0.015), mask*0.92) + vec3(0.22,0.2,0.18)*rim*0.7*smoothstep(0.02, 0.0, uCastT - 0.15);
    vec3 c = plate*uPlate;
    float rimOut = rim;
    // liquid front: spreads from the nearest impact, fast then settling
    vec2 i1 = uImp.xy*vec2(asp,1.), i2 = uImp.zw*vec2(asp,1.);
    vec2 sp = s*vec2(asp,1.);
    float d1 = length(sp - i1), d2 = length(sp - i2);
    float nf = fbm(q*vec2(asp,1.)*22.0)*0.05;
    float R = 0.9, tau = uTau;
    float tf1 = uImpT.x - tau*log(max(1e-4, 1.0 - min(0.999, (d1 + nf)/R)));
    float tf2 = uImpT.y - tau*log(max(1e-4, 1.0 - min(0.999, (d2 + nf)/R)));
    float tf = min(tf1, tf2);
    vec2 ic = tf1 < tf2 ? i1 : i2;
    float age = uCastT - tf;
    float wet = smoothstep(-0.015, 0.02, age)*smoothstep(0.35, 0.6, mask);
    float temp = exp(-max(age, 0.0)/mix(0.6, 0.42, uIron));
    // flow texture radiates from the impact
    vec2 rel = sp - ic; float ang = atan(rel.y, rel.x);
    vec2 fuv = vec2(ang*9.0, length(rel)*26.0 - uCastT*3.2);
    float bm; vec3 liquid = lava(0.4 + 0.55*wet, fuv, temp, bm);
    float meniscus = smoothstep(0.06, 0.0, age)*smoothstep(-0.015, 0.0, age);
    liquid += body(1.25)*meniscus*0.8;
    // cooling skin: cracks glow through as it sets
    vec2 vr = voro(qp*26.0 + fbm(qp*9.0)*0.8);
    float crack = 1.0 - smoothstep(0.0, 0.035, vr.y);
    float skin = smoothstep(0.7, 0.32, temp);
    // cooled: cast iron, sand-textured, with a lit bevel at the cavity edge
    float sand = fbm(qp*90.0)*0.6 + fbm(qp*22.0)*0.4;
    // lit from above: the top bevel catches light, the lower edge falls into shadow
    float bev = clamp(-mg.y*uRes.y*0.5, 0., 1.), sh = clamp(mg.y*uRes.y*0.5, 0., 1.);
    vec3 iron = vec3(0.24, 0.232, 0.224)*(0.7 + 0.6*sand) + vec3(0.7, 0.68, 0.64)*bev*uIron - vec3(0.12)*sh*uIron;
    vec3 setc = mix(mix(vec3(0.06,0.055,0.05), iron, uIron), body(temp*0.9)*0.5, smoothstep(0.1, 0.45, temp));
    setc += body(0.4 + temp)*crack*smoothstep(0.06, 0.38, temp)*0.9;
    liquid = mix(liquid, setc, skin);
    // polish: the sweep turns every cell bone, with a glint
    float pt = mix(uPol0, uPol1, polN);
    float pol = smoothstep(pt, pt + 0.1, uCastT);
    float glint = exp(-pow((uCastT - pt - 0.05)/0.04, 2.0));
    vec3 bone = vec3(0.945, 0.937, 0.918);
    vec3 cell = mix(liquid, bone, pol*(1.0 - uIron)) + vec3(1.2,1.15,1.05)*glint*0.9*mask*(1.0 - uIron);
    // iron finish: one band of light travels the length of the casting
    float dxs = (q.x - uSweep)*asp;
    float band = (exp(-pow(dxs/0.025, 2.0))*0.8 + exp(-pow(dxs/0.16, 2.0))*0.25)*mask*smoothstep(0.35, 0.05, temp)*(0.6 + 0.6*sand);
    cell += vec3(0.75, 0.73, 0.7)*band*uIron;
    c = mix(c, cell, wet);
    // the seams flash molten once, like the windows did
    float seam = clamp(1.0 - textureLod(uLogo, q, 2.2).r*1.15, 0., 1.)*smoothstep(0.3, 0.9, sil);
    float sf = exp(-pow((uCastT - pt - uFlash)/0.07, 2.0));
    c += body(1.0)*seam*sf*2.6*(1.0 - uIron);
    // streams: fall from the top to each impact; the tail falls once the pour stops
    for(int k=0;k<2;k++){
      vec2 imp = k == 0 ? uImp.xy : uImp.zw;
      float top = k == 0 ? uStream.x : uStream.y, wpx = k == 0 ? uStream.z : uStream.w;
      if (wpx <= 0.0 || s.y < top || s.y > imp.y) continue;
      float neck = 0.75 + 0.5*fbm(vec2(s.y*14.0 - uCastT*9.0, float(k)*7.0));
      float wob = (fbm(vec2(s.y*3.0 - uCastT*2.0, float(k)*3.0)) - 0.5)*0.004;
      float hw = wpx*neck*0.5/uRes.x;
      float dx = abs(s.x - imp.x - wob)/max(hw, 1e-5);
      float f = smoothstep(1.25, 0.0, dx);
      float sb; vec3 st = lava(0.3 + 0.7*f, vec2(s.x*uRes.x/wpx*2.0, s.y*7.0 - uCastT*11.0), 1.0, sb);
      c = mix(c, st, sb);
      c += body(0.9)*smoothstep(2.6, 0.8, dx)*0.12;
    }
    // splash glow while a stream feeds its impact
    for(int k=0;k<2;k++){
      vec2 imp = k == 0 ? uImp.xy : uImp.zw;
      float on = (k == 0 ? step(uStream.x, imp.y - 0.002)*step(0.5, uStream.z) : step(uStream.y, imp.y - 0.002)*step(0.5, uStream.w));
      float r = length((s - imp)*vec2(asp,1.));
      c += body(1.1)*exp(-r*r/0.0009)*0.9*on + body(0.7)*exp(-r*r/0.012)*0.25*on;
    }
    return c*uCastFade;
  }
  void main(){
    if (uCast > 0.5) { fragColor = vec4(castColor(vec2(vUv.x, 1.0 - vUv.y)), 1.0); return; }
    vec2 p = vec2(vUv.x, 1.0 - vUv.y);
    p = 0.5 + (p - 0.5)/uZoom + uPan;
    float asp = uRes.x/uRes.y;
    p.y += uTilt;
    float k = mix(1.0, 1.0/0.07, uPinch * smoothstep(0.1, 1.3, p.y));
    float sx = 0.5 + (p.x - 0.5)*k;
    float n1 = fbm(vec2(sx*2.3, uSeed));
    float fing = pow(vnoise(vec2(sx*17.0, uSeed+3.)), 7.0) + 0.6*pow(vnoise(vec2(sx*61.0, uSeed+9.)), 9.0);
    float f2 = uFlow*uFlow;
    float sag = texture(uEdge, clamp(vec2(sx, p.y), 0., 1.)).r;
    float off = f2*(0.10 + 0.5*n1*n1 + 1.4*fing + 0.25*sag);
    float wob = 0.005*uFlow*sin(p.y*23.0 + n1*9.0 + uT*3.0);
    vec2 src = vec2(sx + wob, p.y - off);
    vec3 acc = vec3(0.); float aa = 0., ws = 0.;
    float streak = off*0.32 + 0.001;
    for(int i=0;i<10;i++){
      float s = float(i)/9.0; vec2 q = src - vec2(0., streak*s);
      float inb = step(0.,q.x)*step(q.x,1.)*step(0.,q.y)*step(q.y,1.);
      vec4 t = texture(uScene, q); float w = 1.0 - s*0.6;
      acc += t.rgb*inb*w; aa += t.a*inb*w; ws += w; }
    vec3 col = acc/ws; float alpha = aa/ws;
    float inside = step(0.,src.x)*step(src.x,1.)*step(0.,src.y)*step(src.y,1.);
    vec3 egb = texture(uEdge, clamp(src,0.,1.)).rgb;
    vec2 eg = egb.rg;
    float N = fbm(src*vec2(9.0,6.0) + vec2(0., -uT*0.6) + uSeed);
    float raw = uHeat*2.6 - (1.0 - eg.r)*1.2 - eg.g*0.9 + (N - 0.5)*0.45;
    float heat = smoothstep(0.0, 0.3, raw);
    float band = exp(-pow((raw - 0.12)/0.09, 2.0));
    float on = step(0.0001, uHeat);
    float hm = mix(1.0, egb.b, uHeatMask);     // a single window can burn without its surroundings
    heat *= on*hm; band *= on*hm;
    heat = max(heat, smoothstep(0.0, 0.6, uFlow)*0.9);
    float lum = dot(col, vec3(.2126,.7152,.0722));
    float lumSoft = lumAt(src, 2.5);
    float lh = uLumHeat*smoothstep(0.32, 0.8, lumSoft)*smoothstep(0.2, 0.6, lum);
    vec3 g = mix(grade(col), col, uRaw);
    // contours of the picture itself: where the metal cracks first
    vec2 px = 1.5/uRes;
    float gx = lumAt(src+vec2(px.x,0.),0.) - lumAt(src-vec2(px.x,0.),0.);
    float gy = lumAt(src+vec2(0.,px.y),0.) - lumAt(src-vec2(0.,px.y),0.);
    float edge = smoothstep(0.04, 0.22, length(vec2(gx,gy)));
    // temperature: a plate heating evenly; the picture only modulates it, like scale on hot steel
    float lk = pow(clamp((lum - 0.08)/0.85, 0., 1.), 1.6);
    float T = heat*(0.03 + 0.24*lk + (N - 0.5)*0.06)*uEmber + band*(0.75 + 0.45*lk) + uFlow*0.4*(0.4 + 0.8*lk);
    float hgt = lum*0.6 + N*0.6;
    vec2 grd = vec2(dFdx(hgt), dFdy(hgt))*uRes.y*0.03;
    vec3 nrm = normalize(vec3(-grd, 1.0));
    float spec = pow(max(dot(reflect(normalize(vec3(0.35,-0.55,-1.)), nrm), vec3(0,0,1)), 0.), 40.0);
    // the cooling skin while the heat front passes: dark, with thin cracks
    vec2 vr = voro(src*vec2(asp,1.)*9.0 + N*0.8);
    float front = smoothstep(0.08, 0.3, heat)*(1.0 - smoothstep(0.45, 0.8, heat));
    float crack = (1.0 - smoothstep(0.0, 0.035, vr.y))*front;
    float vein = max(crack, edge*front*0.5);
    vec3 crust = g*0.10 + vec3(0.02,0.018,0.016);
    vec3 molten = mix(crust, body(T), smoothstep(0.3, 0.75, heat));
    molten += body(0.62 + 0.2*lum)*vein*0.9;
    molten += body(T + 0.35)*spec*smoothstep(0.5, 1.0, heat)*0.35;
    float into = smoothstep(0.02, 0.3, heat);
    vec3 c = mix(g, molten, into);
    c = mix(c, g*0.15 + body(0.22 + 1.05*pow(lum, 2.2)), lh);
    c = mix(c, c*smoothstep(0.05, 0.5, lh), uIsolate);   // everything but the metal goes dark
    c *= inside;
    // liquid metal layer: blurred field thresholded into a gooey body, shaded as flowing lava
    vec2 mq = vec2(p.x, p.y/3.0);
    vec2 mt = (p.y >= 0.0 && p.y <= 3.0) ? texture(uMetal, mq).rg : vec2(0.0);
    float fld = mt.x;
    float bodyM;
    vec3 metal = lava(fld, vec2(p.x*uRes.x/14.0, p.y*9.0 - uT*uFlowSpd), 0.92, bodyM);
    c = mix(c, metal, bodyM*uMetalOn);
    c += body(0.5)*smoothstep(0.16, 0.30, fld)*(1.0 - bodyM)*0.25*uMetalOn;
    c += body(0.85 + 0.6*mt.y)*smoothstep(0.0, 0.5, mt.y)*2.4*uMetalOn;   // sparks: emission only
    fragColor = vec4(c, 1.0);
  }`;

  // ---------------------------------------------------------------- the tube: picture -> CRT in a room, or passthrough
  const TV = COMMON + `
  uniform sampler2D uPic, uOff, uLit, uMetal, uAtlas;
  uniform float uWall, uMeltT, uOverheat;
  uniform vec4 uBox;          // one set's tile in plate fractions
  uniform vec2 uAtlasGrid;
  uniform float uT, uTV, uBarrel, uRad, uScrDim, uFlatOn, uPicW, uPower, uFlowSpd2, uFlatRot, uAmber;
  uniform vec3 uCam;          // plate centre x, y (0..1), zoom
  uniform vec4 uScr;          // screen opening in plate fractions
  uniform vec3 uOn;           // dot, openX, openY
  uniform vec4 uFlat;         // the picture pulled out of the tube: rect in output fractions
  float sdBox(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.)) + min(max(q.x, q.y), 0.) - r; }
  vec3 pic(vec2 u){           // picture-space sample (u in 0..1 over the 4:3 picture)
    return texture(uPic, vec2(0.5 + (u.x - 0.5)*uPicW, 1.0 - u.y)).rgb;
  }
  void main(){
    vec2 uv = vec2(vUv.x, 1.0 - vUv.y);
    vec3 c;
    if (uTV < 0.5) {
      c = texture(uPic, vec2(uv.x, 1.0 - uv.y)).rgb;
    } else {
      vec2 w = uCam.xy + (uv - 0.5)/uCam.z;                 // plate coords
      // a wall of sets: every tile of the plane is the same set; the one at (0,0) is ours
      vec2 cell = vec2(0.0);
      if (uWall > 0.5) { vec2 r = (w - uBox.xy)/uBox.zw; cell = floor(r); w = uBox.xy + fract(r)*uBox.zw; }
      float ours = 1.0 - step(0.5, abs(cell.x) + abs(cell.y));
      vec2 pr = vec2(3840.0, 2160.0);
      vec2 sc = uScr.xy + uScr.zw*0.5;
      float d = sdBox((w - sc)*pr, uScr.zw*pr*0.5, uRad*pr.y);
      vec3 off = texture(uOff, w).rgb, lit = texture(uLit, w).rgb;
      float inb = step(0.0, w.x)*step(w.x, 1.0)*step(0.0, w.y)*step(w.y, 1.0);
      float avg = dot(textureLod(uPic, vec2(0.5), 11.0).rgb, vec3(0.3, 0.55, 0.15));
      float spill = mix(0.45, clamp(avg*1.6, 0.0, 1.2), ours)*uOn.z + uOn.x*0.06;
      float hc = 0.0;
      if (uMeltT > 0.0) { float dl = h21(cell + 1.7)*0.5 + length(cell)*0.025; hc = smoothstep(dl, dl + 0.35, uMeltT); spill += hc*1.5; }
      c = (off + max(lit - off, 0.0)*spill)*inb;
      if (d < 1.0) {
        vec2 sl = (w - uScr.xy)/uScr.zw;
        vec2 q = sl*2.0 - 1.0;
        float bar_ = uBarrel*(1.0 + 1.8*uOverheat*ours);
        q *= (1.0 + bar_*dot(q, q))/(1.0 + bar_);
        vec2 u = q*0.5 + 0.5;
        // an overheating set: the picture rolls and tears
        u.y += ours*uOverheat*0.035*sin(uT*31.0)*step(0.6, fract(uT*3.7));
        u.x += ours*uOverheat*0.02*step(0.93, fract(u.y*13.0 + uT*7.0))*sin(uT*90.0);
        vec2 ca = (u - 0.5)*0.0035;
        vec3 img = vec3(pic(u + ca).r, pic(u).g, pic(u - ca).b);
        if (ours < 0.5) { // other sets show other desktops, burnt amber
          float sl_ = floor(h21(cell + 0.37)*uAtlasGrid.x*uAtlasGrid.y);
          vec2 slot = vec2(mod(sl_, uAtlasGrid.x), floor(sl_/uAtlasGrid.x));
          vec3 a_ = texture(uAtlas, (slot + clamp(u, 0.0, 1.0))/uAtlasGrid).rgb;
          float al = dot(a_, vec3(0.3, 0.55, 0.15));
          img = vec3(1.0, 0.60, 0.24)*pow(al, 0.92) + vec3(0.0, 0.22, 0.36)*pow(al, 2.6);
        }
        // the melt: every screen goes molten, in its own time
        float fl = fbm(vec2(u.x*4.0, u.y*2.2 - uT*1.6) + cell*3.1);
        vec3 hot = body(0.42 + 0.5*hc + 0.55*(fl - 0.5) + 0.25*(1.0 - abs(q.y)));
        img = mix(img, hot, hc*0.96);
        float ok = step(0.0, u.x)*step(u.x, 1.0)*step(0.0, u.y)*step(u.y, 1.0);
        // amber phosphor: the tube sees only brightness, and burns it warm
        float pl = dot(img, vec3(0.3, 0.55, 0.15));
        vec3 amber = vec3(1.0, 0.60, 0.24)*pow(max(pl, 0.0), 0.92) + vec3(0.0, 0.22, 0.36)*pow(max(pl, 0.0), 2.6);
        img = mix(img, amber, uAmber);
        // scanlines tighten on bright lines; edges and corners fall off like a real tube
        float lum = dot(img, vec3(0.3, 0.55, 0.15));
        float sl2 = 0.5 + 0.5*cos(u.y*3.14159*2.0*300.0);
        img *= mix(0.72, 1.0, mix(sl2, 1.0, clamp(lum*0.6, 0.0, 0.85)));
        float edge = smoothstep(0.0, 0.16, min(min(u.x, 1.0 - u.x), min(u.y, 1.0 - u.y)));
        img *= mix(0.55, 1.0, edge)*ok;
        // power-on: the dot (the caret), the line, then the raster opens
        float ax = abs(u.x - 0.5), ay = abs(u.y - 0.5);
        float open = step(ax, uOn.y*0.5)*step(ay, uOn.z*0.5);
        img *= open*(1.0 - uScrDim);
        float line = exp(-pow(ay/max(0.002, uOn.z*0.5 + 0.004), 2.0)*6.0)*step(ax, uOn.y*0.5)*(1.0 - smoothstep(0.6, 1.0, uOn.z));
        img += body(1.25)*line*1.6*step(0.001, uOn.y);
        float dot_ = exp(-((ax*ax)*5.0 + ay*ay*0.22)/0.0009);
        img += body(0.95 + 0.25*uOn.x)*dot_*uOn.x*2.2;
        // glass: a dark tube face, a soft reflection, a bevel at the opening
        vec3 glass = vec3(0.012, 0.014, 0.016) + vec3(0.06, 0.065, 0.07)*smoothstep(0.9, 0.0, length((sl - vec2(0.28, 0.22))*vec2(1.0, 1.6)))*0.6;
        glass += body(0.45 + 0.3*uOverheat)*uOverheat*ours*0.35*smoothstep(0.2, 1.0, length(q));
        c = mix(c, glass + img, smoothstep(1.0, -1.5, d));
      }
      // the picture pulled out of the tube: flat, crisp, with a shadow on the set
      if (uFlatOn > 0.5) {
        vec2 fc = uFlat.xy + uFlat.zw*0.5;
        vec2 fs = (uv - fc)*vec2(16.0/9.0, 1.0);
        float cr = cos(uFlatRot), sr = sin(uFlatRot);
        fs = vec2(cr*fs.x + sr*fs.y, -sr*fs.x + cr*fs.y);
        vec2 fu = fs/vec2(16.0/9.0, 1.0)/uFlat.zw + 0.5;
        float sd = sdBox(fs, uFlat.zw*0.5*vec2(16.0/9.0, 1.0), 0.004);
        vec2 shs = fs - vec2(0.012, -0.03);
        c *= mix(1.0, 0.35, smoothstep(0.12, -0.02, sdBox(shs, uFlat.zw*0.5*vec2(16.0/9.0, 1.0), 0.004)));
        c *= mix(1.0, 0.25, smoothstep(0.09, -0.01, sd));
        if (sd < 0.0) c = pic(fu);
      }
    }
    // world-space liquid (blue channel of the metal layer): metal that leaves the screen
    float fb = texture(uMetal, vec2(uv.x, uv.y/3.0)).b;
    float bm; vec3 lv = lava(fb, vec2(uv.x*uRes.x/14.0, uv.y*9.0 - uT*uFlowSpd2), 0.92, bm);
    c = mix(c, lv, bm) + body(0.5)*smoothstep(0.16, 0.30, fb)*(1.0 - bm)*0.25;
    fragColor = vec4(c, 1.0);
  }`;

  const BRIGHT = COMMON + `
  uniform sampler2D uSrc;
  void main(){ vec3 c = texture(uSrc, vUv).rgb; float m = max(c.r, max(c.g, c.b));
    fragColor = vec4(c*smoothstep(0.95, 2.4, m), 1.0); }`;

  const BLUR = COMMON + `
  uniform sampler2D uSrc; uniform vec2 uDir;
  void main(){
    vec3 c = texture(uSrc, vUv).rgb*0.2270270270;
    c += (texture(uSrc, vUv + uDir*1.3846153846).rgb + texture(uSrc, vUv - uDir*1.3846153846).rgb)*0.3162162162;
    c += (texture(uSrc, vUv + uDir*3.2307692308).rgb + texture(uSrc, vUv - uDir*3.2307692308).rgb)*0.0702702703;
    fragColor = vec4(c, 1.0); }`;

  const FINAL = COMMON + `
  uniform sampler2D uHdr, uB1, uB2; uniform vec2 uWeave, uBlur; uniform float uFrame, uExposure, uFade, uGrain;
  vec3 shoulder(vec3 x){ vec3 k = vec3(0.78); return mix(x, k + (1.0-k)*(1.0 - exp(-(x-k)/(1.0-k))), step(k, x)); }
  void main(){
    vec2 uv = vUv + uWeave/uRes;
    vec3 c = vec3(0.), b = vec3(0.);
    // directional shutter blur for whips (uBlur in px); 1 tap when still
    int n = length(uBlur) > 0.5 ? 16 : 1;
    for(int i=0;i<16;i++){ if(i>=n) break;
      vec2 q = uv + uBlur/uRes*(n > 1 ? float(i)/15.0 - 0.5 : 0.0);
      c += texture(uHdr, q).rgb; b += texture(uB1, q).rgb*0.35 + texture(uB2, q).rgb*0.6; }
    c /= float(n); b /= float(n);
    c += b*vec3(1.0,0.45,0.22);
    c = shoulder(c*uExposure);
    vec2 q = vUv - 0.5; c *= 1.0 - dot(q*vec2(1.0,0.8), q)*0.9;
    uvec3 q3 = uvec3(uvec2(vUv*uRes), uint(uFrame));
    q3 = q3*1664525u + 1013904223u; q3.x += q3.y*q3.z; q3.y += q3.z*q3.x; q3.z += q3.x*q3.y;
    q3 ^= q3 >> 16u; q3.x += q3.y*q3.z; q3.y += q3.z*q3.x; q3.z += q3.x*q3.y;
    float g = float(q3.x & 0xffffu)/65535.0 - 0.5;
    c += g*uGrain*(0.55 + 0.45*(1.0 - c.g));
    fragColor = vec4(clamp(c, 0., 1.)*uFade, 1.0);
  }`;

  function prog(fs) {
    const mk = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
    const p = gl.createProgram();
    gl.attachShader(p, mk(gl.VERTEX_SHADER, VS)); gl.attachShader(p, mk(gl.FRAGMENT_SHADER, fs));
    gl.bindAttribLocation(p, 0, "a"); gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const u = {}; const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) { const name = gl.getActiveUniform(p, i).name; u[name] = gl.getUniformLocation(p, name); }
    return { p, u };
  }
  const P = { scene: prog(SCENE), tv: prog(TV), bright: prog(BRIGHT), blur: prog(BLUR), final: prog(FINAL) };

  const vb = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vb);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

  function tex(w, h, hdr) {
    const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
    if (hdr && halfFloat) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.HALF_FLOAT, null);
    else gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }
  function target(w, h) { const t = tex(w, h, true); const f = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, f);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0); return { t, f, w, h }; }
  const RT = { pic: target(W, H), hdr: target(W, H), a4: target(W / 4, H / 4), b4: target(W / 4, H / 4), a8: target(W / 8, H / 8), b8: target(W / 8, H / 8) };
  gl.bindTexture(gl.TEXTURE_2D, RT.pic.t); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
  const T = { scene: tex(W, H, false), edge: tex(W, H, false), metal: tex(W / 2, H * 1.5, false), logo: tex(W * 2, H * 2, false), off: tex(8, 8, false), lit: tex(8, 8, false), atlas: tex(W, H, false) };

  for (const t of [T.scene, T.logo, T.off, T.lit]) { gl.bindTexture(gl.TEXTURE_2D, t); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR); }
  function upload(t, source) {
    gl.bindTexture(gl.TEXTURE_2D, t); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    if (t === T.scene || t === T.logo || t === T.off || t === T.lit) gl.generateMipmap(gl.TEXTURE_2D);
  }
  function pass(pr, rt, set) {
    gl.useProgram(pr.p); gl.bindFramebuffer(gl.FRAMEBUFFER, rt ? rt.f : null);
    gl.viewport(0, 0, rt ? rt.w : W, rt ? rt.h : H); set(pr.u); gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  function bind(unit, t, loc) { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, t); gl.uniform1i(loc, unit); }

  // s: { scene: canvas, edge: canvas|null, t, heat, flow, pinch, tilt, zoom, lumHeat, seed, frame, exposure, fade }
  function draw(s) {
    upload(T.scene, s.scene);
    if (s.edge && s.edge !== draw._edge) { upload(T.edge, s.edge); draw._edge = s.edge; }
    if (s.metal) upload(T.metal, s.metal);
    if (s.logo && s.logo !== draw._logo) { upload(T.logo, s.logo); draw._logo = s.logo; }
    if (s.atlas) upload(T.atlas, s.atlas);
    if (s.plates && s.plates !== draw._plates) { upload(T.off, s.plates.off); upload(T.lit, s.plates.lit); draw._plates = s.plates; }
    pass(P.scene, RT.pic, (u) => {
      bind(0, T.scene, u.uScene); bind(1, T.edge, u.uEdge); bind(2, T.metal, u.uMetal);
      gl.uniform1f(u.uEmber, s.ember == null ? 1 : s.ember); gl.uniform1f(u.uMetalOn, s.metal ? 1 : 0);
      gl.uniform1f(u.uSat, s.sat == null ? 0.22 : s.sat); gl.uniform1f(u.uRaw, s.raw || 0);
      gl.uniform2f(u.uPan, s.panX || 0, s.panY || 0);
      gl.uniform1f(u.uIsolate, s.isolate || 0); gl.uniform1f(u.uContrast, s.contrast || 1); gl.uniform1f(u.uAmberS, s.amber || 0); gl.uniform1f(u.uHeatMask, s.heatMask || 0); gl.uniform1f(u.uFlowSpd, s.flowSpd == null ? 4 : s.flowSpd);
      bind(3, T.logo, u.uLogo);
      const c = s.cast;
      gl.uniform1f(u.uCast, c ? 1 : 0);
      if (c) {
        gl.uniform1f(u.uCastT, c.t); gl.uniform1f(u.uPlate, c.plate); gl.uniform1f(u.uPol0, c.pol0); gl.uniform1f(u.uPol1, c.pol1);
        gl.uniform1f(u.uFlash, c.flash); gl.uniform1f(u.uIron, c.iron || 0); gl.uniform1f(u.uSweep, c.sweep == null ? -1 : c.sweep);
        gl.uniform1f(u.uCastFade, c.fade == null ? 1 : c.fade); gl.uniform1f(u.uTau, c.tau || 0.62); gl.uniform4f(u.uImp, ...c.imp); gl.uniform4f(u.uStream, ...c.stream); gl.uniform2f(u.uImpT, ...c.impT);
      }
      gl.uniform2f(u.uRes, W, H); gl.uniform1f(u.uT, s.t); gl.uniform1f(u.uHeat, s.heat); gl.uniform1f(u.uFlow, s.flow);
      gl.uniform1f(u.uPinch, s.pinch); gl.uniform1f(u.uTilt, s.tilt); gl.uniform1f(u.uSeed, s.seed || 0);
      gl.uniform1f(u.uZoom, s.zoom || 1); gl.uniform1f(u.uLumHeat, s.lumHeat || 0);
    });
    gl.bindTexture(gl.TEXTURE_2D, RT.pic.t); gl.generateMipmap(gl.TEXTURE_2D);
    pass(P.tv, RT.hdr, (u) => {
      const v = s.tv;
      bind(0, RT.pic.t, u.uPic); bind(1, T.off, u.uOff); bind(2, T.lit, u.uLit); bind(3, T.metal, u.uMetal);
      gl.uniform2f(u.uRes, W, H); gl.uniform1f(u.uT, s.t); gl.uniform1f(u.uFlowSpd2, s.flowSpd2 == null ? 7 : s.flowSpd2);
      gl.uniform1f(u.uTV, v ? 1 : 0);
      if (v) {
        gl.uniform3f(u.uCam, v.cx, v.cy, v.zoom); gl.uniform4f(u.uScr, ...v.scr); gl.uniform1f(u.uRad, v.rad);
        gl.uniform1f(u.uBarrel, v.barrel); gl.uniform3f(u.uOn, ...v.on); gl.uniform1f(u.uScrDim, v.dim || 0);
        gl.uniform1f(u.uPicW, 0.75); gl.uniform1f(u.uAmber, v.amber == null ? 1 : v.amber); gl.uniform1f(u.uWall, v.box ? 1 : 0); gl.uniform4f(u.uBox, ...(v.box || [0, 0, 1, 1]));
        gl.uniform1f(u.uMeltT, v.meltT == null ? -1 : v.meltT); gl.uniform1f(u.uOverheat, v.overheat || 0); gl.uniform2f(u.uAtlasGrid, 8, 6);
        bind(4, T.atlas, u.uAtlas); gl.uniform1f(u.uFlatOn, v.flat ? 1 : 0); gl.uniform1f(u.uFlatRot, v.flatRot || 0); gl.uniform4f(u.uFlat, ...(v.flat || [0, 0, 1, 1]));
      }
    });
    pass(P.bright, RT.a4, (u) => bind(0, RT.hdr.t, u.uSrc));
    pass(P.blur, RT.b4, (u) => { bind(0, RT.a4.t, u.uSrc); gl.uniform2f(u.uDir, 4 / W, 0); });
    pass(P.blur, RT.a4, (u) => { bind(0, RT.b4.t, u.uSrc); gl.uniform2f(u.uDir, 0, 4 / H); });
    pass(P.blur, RT.a8, (u) => { bind(0, RT.a4.t, u.uSrc); gl.uniform2f(u.uDir, 12 / W, 0); });
    pass(P.blur, RT.b8, (u) => { bind(0, RT.a8.t, u.uSrc); gl.uniform2f(u.uDir, 0, 12 / H); });
    pass(P.final, null, (u) => {
      bind(0, RT.hdr.t, u.uHdr); bind(1, RT.a4.t, u.uB1); bind(2, RT.b8.t, u.uB2);
      gl.uniform2f(u.uRes, W, H); gl.uniform1f(u.uFrame, s.frame % 977);
      const f = s.frame;
      gl.uniform2f(u.uWeave, (window.L.hash(f * 3 + 1) - 0.5) * 1.6, (window.L.hash(f * 7 + 2) - 0.5) * 1.6);
      gl.uniform2f(u.uBlur, s.blurX || 0, s.blurY || 0); gl.uniform1f(u.uGrain, s.grain == null ? 0.07 : s.grain);
      gl.uniform1f(u.uExposure, s.exposure || 1); gl.uniform1f(u.uFade, s.fade == null ? 1 : s.fade);
    });
  }
  window.GL = { draw, W, H };
})();
