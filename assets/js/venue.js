import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const ASSETS=window.ASSETS;
const L10N=window.VENUE_LANG||'id';

/* ---------------- data ---------------- */
const PHASES = [
  {id:'art', tab:{id:'Artistik',en:'Artistic'}, d:{id:'12–15 Des',en:'12–15 Dec'}},
  {id:'rg', tab:{id:'Ritmik',en:'Rhythmic'}, d:{id:'16–18 Des',en:'16–18 Dec'}},
  {id:'aer', tab:{id:'Aerobik',en:'Aerobic'}, d:{id:'19–20 Des',en:'19–20 Dec'}},
];

/* ---------------- three setup ---------------- */
const stage=document.getElementById('stage');
let renderer;
try{
  renderer=new THREE.WebGLRenderer({antialias:true});
}catch(e){document.getElementById('err').style.display='grid';document.getElementById('loading').remove();throw e;}
renderer.setPixelRatio(Math.min(window.devicePixelRatio,2));
renderer.shadowMap.enabled=true;
renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputColorSpace=THREE.SRGBColorSpace;
renderer.toneMapping=THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure=1.05;
stage.prepend(renderer.domElement);

const scene=new THREE.Scene();
scene.background=new THREE.Color('#cfdbe9');
scene.fog=new THREE.Fog('#cfdbe9',220,420);
const camera=new THREE.PerspectiveCamera(45,1,0.1,1000);
const controls=new OrbitControls(camera,renderer.domElement);
controls.enableDamping=true; controls.dampingFactor=.08;
controls.maxPolarAngle=Math.PI*0.495; controls.minDistance=3; controls.maxDistance=320;

scene.add(new THREE.HemisphereLight('#ffffff','#7d8a6a',1.1));
const sun=new THREE.DirectionalLight('#fff6e8',1.6);
sun.position.set(60,110,45); sun.castShadow=true;
sun.shadow.mapSize.set(2048,2048);
Object.assign(sun.shadow.camera,{left:-75,right:75,top:75,bottom:-75,near:10,far:300});
sun.shadow.bias=-0.0004;
scene.add(sun);
const hallLight=new THREE.PointLight('#ffffff',250,60,1.6); hallLight.position.set(0,11,0); scene.add(hallLight);

/* materials */
const M=(c,o={})=>new THREE.MeshStandardMaterial(Object.assign({color:c,roughness:.85,metalness:0},o));
const mat={
  grass:M('#8fa877'), road:M('#6e737b'), paving:M('#a9a39a'), dirt:M('#c9a27a'),
  wallOut:M('#e9e6dc'), wallIn:M('#efeadc'), yellow:M('#e3b23c'), roofGrey:M('#b9bec6',{side:THREE.DoubleSide,roughness:.6,metalness:.2}),
  hallFloor:M('#3d7458'), strip:M('#b98a3e'), stepTread:M('#8d939b'), stepRiser:M('#3f8a55'),
  rail:M('#8cc63f',{roughness:.5}), steel:M('#d9dde3',{roughness:.35,metalness:.6}), white:M('#f4f5f7'),
  dark:M('#1d232c'), glass:M('#5e7488',{roughness:.2,metalness:.3}), neighbour:M('#d7d3cb'),
  tree:M('#4f7a3d'), trunk:M('#6b5137'),
  artFloor:M('#8fb3d9'), artBorder:M('#3f6aa8'), rgCarpet:M('#e6d3a8'), rgBorder:M('#c9b07a'),
  aerFloor:M('#9fb7cf'), aerBorder:M('#3f8a55'), warm:M('#d9c9a4'), warmAer:M('#a9bccc'),
  mat:M('#2f4ea0'), matTop:M('#3557b3'), runway:M('#6f95c8'), red:M('#c8473a'), navy:M('#13284a'),
  beam:M('#c7a77a'), leather:M('#7a4a2b'), pit:M('#2a3e7a')
};

/* ---------------- texture helpers ---------------- */
const imgCache={};
function loadImg(k){ if(imgCache[k]) return imgCache[k]; const p=new Promise(r=>{const i=new Image(); i.onload=()=>r(i); i.onerror=()=>r(null); i.src=ASSETS[k];}); imgCache[k]=p; return p; }
const texJobs=[];
function canvasTex(w,h,draw){
  const c=document.createElement('canvas'); c.width=w; c.height=h;
  const t=new THREE.CanvasTexture(c); t.colorSpace=THREE.SRGBColorSpace; t.anisotropy=8;
  const job=async()=>{ const ctx=c.getContext('2d'); ctx.clearRect(0,0,w,h); await draw(ctx,w,h); t.needsUpdate=true; };
  texJobs.push(job); job(); return t;
}
async function drawImgFit(ctx,k,x,y,w,h,align='center'){
  const im=await loadImg(k); if(!im) return;
  const s=Math.min(w/im.width,h/im.height); const dw=im.width*s, dh=im.height*s;
  const dx= align==='left'? x : x+(w-dw)/2; ctx.drawImage(im,dx,y+(h-dh)/2,dw,dh);
}
const F=(wt,px)=>`${wt} ${px}px 'Hanken Grotesk', system-ui, sans-serif`;

const texBackdrop=canvasTex(1880,1034,async(ctx,w,h)=>{
  const g=ctx.createLinearGradient(0,0,w,h); g.addColorStop(0,'#1b3a66'); g.addColorStop(1,'#0e1f3b');
  ctx.fillStyle=g; ctx.fillRect(0,0,w,h);
  const st=await loadImg('starGold'); if(st){ctx.globalAlpha=.28; ctx.drawImage(st,w-560,-160,640,640); ctx.globalAlpha=1;}
  const sr=await loadImg('stringRed'); if(sr){ctx.globalAlpha=.9; ctx.drawImage(sr,w-430,h-300,360,263); ctx.globalAlpha=1;}
  ctx.fillStyle='#e4c87d'; ctx.fillRect(0,0,w,26);
  await drawImgFit(ctx,'joWhite',110,120,560,380,'left');
  ctx.fillStyle='rgba(255,255,255,.4)'; ctx.fillRect(700,170,3,280);
  await drawImgFit(ctx,'giWhite',740,190,430,210,'left');
  ctx.fillStyle='#fff'; ctx.font=F(800,92); ctx.fillText('Kejuaraan Gimnastik',110,620);
  ctx.fillStyle='#e4c87d'; ctx.fillText('Jabar Open 2026',110,720);
  ctx.fillStyle='rgba(255,255,255,.85)'; ctx.font=F(500,44); ctx.fillText('12–20 Desember 2026 · Gymnasium Arcamanik, Bandung',110,800);
  for(let i=0;i<7;i++){ ctx.strokeStyle='rgba(255,255,255,.55)'; ctx.setLineDash([12,10]); ctx.lineWidth=3;
    ctx.strokeRect(110+i*200,870,170,110); }
  ctx.setLineDash([]); ctx.fillStyle='rgba(255,255,255,.7)'; ctx.font=F(600,24);
  for(let i=0;i<7;i++) ctx.fillText('Sponsor',110+i*200+40,935);
});
const texSide=canvasTex(1400,678,async(ctx,w,h)=>{
  ctx.fillStyle='#ffffff'; ctx.fillRect(0,0,w,h);
  const sn=await loadImg('stringNavy'); if(sn){ctx.globalAlpha=.16; ctx.drawImage(sn,w-620,h-300,600,238); ctx.globalAlpha=1;}
  ctx.fillStyle='#2c4c7b'; ctx.fillRect(0,0,28,h); ctx.fillStyle='#e4c87d'; ctx.fillRect(28,0,10,h);
  await drawImgFit(ctx,'joColor',90,70,420,300,'left');
  await drawImgFit(ctx,'giColor',90,400,330,170,'left');
  ctx.fillStyle='#13284a'; ctx.font=F(800,96); ctx.fillText('Jatuh, bangun,',580,250); ctx.fillText('tampil!',580,355);
  ctx.fillStyle='#5b6b88'; ctx.font=F(600,44); ctx.fillText('Artistik · Ritmik · Aerobik',580,470);
  ctx.fillStyle='#2c4c7b'; ctx.font=F(700,38); ctx.fillText('@gimnastikjabar',580,560);
});
const texStandee=canvasTex(660,806,async(ctx,w,h)=>{
  ctx.fillStyle='#13284a'; ctx.fillRect(0,0,w,h);
  const st=await loadImg('starGold'); if(st){ctx.globalAlpha=.9; ctx.drawImage(st,w-230,30,190,190); ctx.globalAlpha=1;}
  await drawImgFit(ctx,'joWhite',60,230,540,300);
  ctx.fillStyle='#e4c87d'; ctx.fillRect(60,580,540,4);
  ctx.fillStyle='#fff'; ctx.font=F(700,46); ctx.textAlign='center'; ctx.fillText('Tace et ostende.',w/2,660);
  ctx.fillStyle='rgba(255,255,255,.7)'; ctx.font=F(500,30); ctx.fillText('Diam dan buktikan.',w/2,710); ctx.textAlign='left';
});
const texLED=canvasTex(1024,410,async(ctx,w,h)=>{
  ctx.fillStyle='#05080d'; ctx.fillRect(0,0,w,h);
  await drawImgFit(ctx,'joWhite',40,50,330,310);
  ctx.fillStyle='#e4c87d'; ctx.font=F(800,58); ctx.fillText('JABAR OPEN 2026',410,170);
  ctx.fillStyle='#fff'; ctx.font=F(500,38); ctx.fillText('Kejuaraan Gimnastik',410,235);
  ctx.fillStyle='#8fb3d9'; ctx.font=F(600,32); ctx.fillText('Hasil langsung · gimnastikjabaropen2026.com',410,300);
});
const texSign=canvasTex(1600,200,async(ctx,w,h)=>{
  ctx.fillStyle='#b9bec6'; ctx.fillRect(0,0,w,h);
  ctx.fillStyle='#e3b23c'; ctx.font=F(700,130); ctx.textAlign='center'; ctx.fillText('Gymnasium',w/2,148);
});
const texSkirt=canvasTex(1024,256,async(ctx,w,h)=>{
  ctx.fillStyle='#13284a'; ctx.fillRect(0,0,w,h); ctx.fillStyle='#e4c87d'; ctx.fillRect(0,0,w,10);
  await drawImgFit(ctx,'joWhite',30,40,230,180,'left');
  ctx.fillStyle='#fff'; ctx.font=F(700,64); ctx.fillText('Meja Juri',300,150);
});
const texPodium=(n)=>canvasTex(256,256,async(ctx,w,h)=>{ctx.fillStyle='#ffffff';ctx.fillRect(0,0,w,h);ctx.fillStyle='#2c4c7b';ctx.font=F(800,150);ctx.textAlign='center';ctx.fillText(String(n),w/2,180);ctx.fillStyle='#e4c87d';ctx.fillRect(0,h-20,w,20);});
const texMedis=canvasTex(512,256,async(ctx,w,h)=>{ctx.fillStyle='#fff';ctx.fillRect(0,0,w,h);ctx.fillStyle='#c8473a';ctx.fillRect(60,88,120,40);ctx.fillRect(100,48,40,120);ctx.fillStyle='#13284a';ctx.font=F(800,80);ctx.fillText('Medis',210,140);});
const texKC=canvasTex(1024,512,async(ctx,w,h)=>{ctx.fillStyle='#2c4c7b';ctx.fillRect(0,0,w,h);await drawImgFit(ctx,'joWhite',60,60,300,260,'left');ctx.fillStyle='#fff';ctx.font=F(800,110);ctx.fillText('Kiss & Cry',400,230);ctx.fillStyle='#e4c87d';ctx.font=F(600,50);ctx.fillText('Jabar Open 2026',400,310);});
document.fonts && document.fonts.load("800 40px 'Hanken Grotesk'").then(()=>texJobs.forEach(j=>j()));

/* ---------------- builders ---------------- */
const pickables=[];
const labels=[]; let curOwner=null;
function info(obj){
  obj.traverse(o=>{ if(o.isMesh) pickables.push(o); o.userData.root=obj; });
  return obj;
}
function addLabel(text,pos,cls='',far=false){
  const el=document.createElement('div'); el.className='lbl'+(typeof cls==='string'&&cls?' '+cls:'');
  const [a,b]=String(text).split('|'); const s1=document.createElement('span'); s1.textContent=a; el.appendChild(s1);
  if(b){ const s2=document.createElement('small'); s2.textContent=b; el.appendChild(s2); }
  document.getElementById('labels').appendChild(el);
  const L={el,pos:new THREE.Vector3(...pos),owner:curOwner,far}; labels.push(L); return L;
}
function box(w,h,d,m,x=0,y=0,z=0,parent){
  const g=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),m); g.position.set(x,y+h/2,z);
  g.castShadow=true; g.receiveShadow=true; parent&&parent.add(g); return g;
}
function cyl(r,h,m,x,y,z,parent,rx=0,rz=0){
  const g=new THREE.Mesh(new THREE.CylinderGeometry(r,r,h,10),m); g.position.set(x,y,z); g.rotation.set(rx,0,rz);
  g.castShadow=true; parent&&parent.add(g); return g;
}
function plane(w,d,m,x,y,z,parent){
  const g=new THREE.Mesh(new THREE.PlaneGeometry(w,d),m); g.rotation.x=-Math.PI/2; g.position.set(x,y,z);
  g.receiveShadow=true; parent&&parent.add(g); return g;
}
function lines(points,color,parent){
  const g=new THREE.BufferGeometry().setFromPoints(points.map(p=>new THREE.Vector3(...p)));
  const l=new THREE.LineSegments(g,new THREE.LineBasicMaterial({color})); parent&&parent.add(l); return l;
}
function quad(p,m){ const g=new THREE.BufferGeometry(); g.setAttribute('position',new THREE.Float32BufferAttribute(p.flat(),3)); g.setIndex([0,1,2,0,2,3]); g.computeVertexNormals(); const q=new THREE.Mesh(g,m); q.castShadow=true; q.receiveShadow=true; return q; }
function texMat(t){ return new THREE.MeshStandardMaterial({map:t,roughness:.7}); }
function panel(w,h,t,x,y,z,ry,parent){
  const g=new THREE.Group();
  const face=new THREE.Mesh(new THREE.PlaneGeometry(w,h),texMat(t)); face.position.z=0.03;
  const back=new THREE.Mesh(new THREE.BoxGeometry(w,h,0.05),mat.white);
  g.add(back,face); g.position.set(x,y+h/2,z); g.rotation.y=ry; parent&&parent.add(g); return g;
}

/* ---------------- site (map frame, rotated) ---------------- */
const site=new THREE.Group(); site.rotation.y=THREE.MathUtils.degToRad(14); scene.add(site);
plane(520,520,mat.grass,0,0,0,site);
function road(pts,w,m=mat.road,y=0.03){
  for(let i=0;i<pts.length-1;i++){
    const [x1,z1]=pts[i],[x2,z2]=pts[i+1]; const dx=x2-x1,dz=z2-z1,len=Math.hypot(dx,dz);
    const s=new THREE.Mesh(new THREE.PlaneGeometry(len+w*0.6,w),m); s.rotation.x=-Math.PI/2; s.rotation.z=-Math.atan2(dz,dx);
    s.position.set((x1+x2)/2,y,(z1+z2)/2); s.receiveShadow=true; site.add(s);
  }
}
road([[-200,-5],[-110,12],[-35,28],[0,35],[43,44],[65,45],[104,35],[132,17],[140,-18],[140,-67],[128,-110]],8);
road([[49,44],[49,17],[32,-7],[18,-26],[0,-33],[-9,-46],[-10,-67],[1,-88],[20,-120]],6);
road([[-10,-70],[-35,-71],[-56,-65],[-65,-49],[-63,-32],[-44,-11]],6);
const dirt=new THREE.Mesh(new THREE.CircleGeometry(48,48,Math.PI*0.55,Math.PI*0.9),mat.dirt); dirt.rotation.x=-Math.PI/2; dirt.position.set(70,0.02,-70); site.add(dirt);
info(box(30,7,28,mat.neighbour,-36,0,-40,site));
addLabel('Padepokan Pencak Silat|Pencak silat hall',[-36,9,-40]).siteLocal=true;
box(16,4,9,mat.neighbour,38,0,30,site); box(18,4,9,mat.neighbour,60,0,32,site);
for(let i=0;i<6;i++) box(14,5,12,mat.neighbour,-150+i*30,0,58+i*3,site);
addLabel('Jl. Pacuan Kuda',[-20,2,31]).siteLocal=true;
addLabel('Lapangan softball|Softball field',[70,2,-70]).siteLocal=true;
// trees
const treeGeo=new THREE.SphereGeometry(1,10,8);
const rng=(s=>()=>((s=Math.sin(s)*10000)-Math.floor(s)))(7);
for(let i=0;i<80;i++){
  const a=rng()*Math.PI*2, r=40+rng()*60; const x=Math.cos(a)*r, z=Math.sin(a)*r*0.8;
  if(Math.abs(z)<44 && Math.abs(x)<48) continue; if(x>20&&x<120&&z<-25&&z>-118) continue;
  const t=new THREE.Group(); const s=2.5+rng()*2.5;
  const c=new THREE.Mesh(treeGeo,mat.tree); c.scale.set(s,s*0.85,s); c.position.y=s+2.2; c.castShadow=true;
  const tr=new THREE.Mesh(new THREE.CylinderGeometry(.25,.35,2.6,6),mat.trunk); tr.position.y=1.3;
  t.add(c,tr); t.position.set(x,0,z); site.add(t);
}

/* ---------------- building (building frame) ---------------- */
// hall: x along 35 m (east +x), z across (north -z). Competition room 35 x 25.
const bld=new THREE.Group(); scene.add(bld);
const HL=35, HW=25, SD=6, EAVE=10, APEX=14;
const WZ=HW/2+SD; // 18.5 outer long walls
// floors
plane(HL,HW,mat.hallFloor,0,0.02,0,bld);
plane(HL,0.6,mat.strip,0,0.025,-HW/2+0.3,bld); plane(HL,0.6,mat.strip,0,0.025,HW/2-0.3,bld);
info(plane(HL,HW,new THREE.MeshBasicMaterial({visible:false}),0,0.03,0,bld));
const outdoorPaving=plane(HL+2*14+8,2*WZ+16,mat.paving,0,0.012,0,bld);

// stands both sides
const walls={};
['n','s'].forEach(side=>{
  const sg=new THREE.Group(); const sgn= side==='n'?-1:1; bld.add(sg);
  box(HL,2.3,0.35,mat.wallIn,0,0,sgn*(HW/2+0.17),sg);
  const rows=8; for(let r=0;r<rows;r++){
    const z=sgn*(HW/2+0.35+0.7*r+0.35); const y=2.3+0.375*r;
    box(HL-2,0.08,0.7,mat.stepTread,0,y,z,sg); box(HL-2,y,0.06,mat.stepRiser,0,0,z-sgn*0.35,sg);
  }
  // rail
  const rp=[]; for(let x=-HL/2+0.5;x<=HL/2-0.5;x+=1.5){rp.push([x,2.3,sgn*(HW/2+0.2)],[x,3.3,sgn*(HW/2+0.2)]);}
  rp.push([-HL/2+0.5,3.3,sgn*(HW/2+0.2)],[HL/2-0.5,3.3,sgn*(HW/2+0.2)]); lines(rp,'#8cc63f',sg);
  info(sg);
  addLabel(side==='n'?'Tribun utara|North stand':'Tribun selatan|South stand',[0,6.4,sgn*(HW/2+3)]);
  // back wall with clerestory
  const w=new THREE.Group(); bld.add(w);
  box(HL,7,0.3,mat.wallOut,0,0,sgn*WZ,w);
  box(HL,EAVE-7,0.25,mat.glass,0,7,sgn*WZ,w);
  walls[side]=w;
});

// end walls
const endE=new THREE.Group(), endW=new THREE.Group(); bld.add(endE,endW);
function endWall(g,x){
  const sh=new THREE.Shape(); sh.moveTo(-WZ,0); sh.lineTo(WZ,0); sh.lineTo(WZ,EAVE);
  for(let i=0;i<=24;i++){const t=i/24; const z=WZ-2*WZ*t; sh.lineTo(z,EAVE+(APEX-EAVE)*(1-Math.pow(z/WZ,2)));}
  sh.lineTo(-WZ,0);
  const hole=new THREE.Path(); hole.moveTo(-5,0.02); hole.lineTo(-3,0.02); hole.lineTo(-3,2.5); hole.lineTo(-5,2.5); hole.lineTo(-5,0.02); sh.holes.push(hole);
  const m=new THREE.Mesh(new THREE.ShapeGeometry(sh),new THREE.MeshStandardMaterial({color:'#efeadc',side:THREE.DoubleSide,roughness:.9}));
  m.rotation.y=Math.PI/2; m.position.x=x; m.receiveShadow=true; g.add(m); return m;
}
const endMeshes=[endWall(endE,HL/2),endWall(endW,-HL/2)];

// EAST end (+x): officials box, LED, glass doors -> lobby/entrance annex
const ex=HL/2-0.05;
box(0.2,3.3,7,mat.glass,ex-0.1,0,-1,endE);
const boxG=new THREE.Group(); endE.add(boxG);
box(1.2,0.25,9,mat.wallIn,ex-0.6,3.3,0,boxG);
box(0.15,3.4,9,mat.glass,ex-0.08,3.55,0,boxG);
const bp=[]; for(let z=-4.5;z<=4.5;z+=0.75) bp.push([ex-1.2,3.55,z],[ex-1.2,4.55,z]); bp.push([ex-1.2,4.55,-4.5],[ex-1.2,4.55,4.5]); lines(bp,'#8cc63f',boxG);
info(boxG);
addLabel('Box resmi|Officials’ box',[ex-1,7.2,-5.6]);
const led=panel(6,2.4,texLED,ex-0.2,7.3,0,-Math.PI/2,endE);
info(led);

// WEST end (-x): backdrop wall
const wx=-HL/2+0.06;
box(0.1,3.2,8,mat.dark,wx,6,0,endW);
const bd=panel(5.88,3.23,texBackdrop,wx+0.08,0.6,0,Math.PI/2,endW);
info(bd);
addLabel('Backdrop',[wx+0.3,4.4,0]);
[-6.4,6.4].forEach(z=>{ const s=panel(1.98,2.42,texStandee,wx+0.5,0,z,Math.PI/2,endW);
  info(s); });
// podium
const podTex=[1,2,3].map(n=>texPodium(n));
function podium(g,x,z,ry){
  const pod=new THREE.Group(); pod.position.set(x,0,z); pod.rotation.y=ry; g.add(pod);
  [[0,0.6,1],[-1.4,0.42,2],[1.4,0.3,3]].forEach(([dx,h,n])=>{ box(1.2,h,1.0,mat.white,dx,0,0,pod);
    const f=new THREE.Mesh(new THREE.PlaneGeometry(1.2,h),texMat(podTex[n-1])); f.position.set(dx,h/2,0.51); pod.add(f); });
  info(pod);
  addLabel('Podium',[x,1.6,z]);
}
// stand-front panels near west end
[-1,1].forEach(sgn=>{ const p=panel(4.67,2.26,texSide,-HL/2+4.2,0,sgn*(HW/2-0.05),sgn<0?0:Math.PI,bld);
  info(p); });

// roof (barrel vault) + space frame
const roofG=new THREE.Group(); bld.add(roofG);
{
  const seg=32, len=HL+7; const geo=new THREE.BufferGeometry(); const pos=[],idx=[];
  for(let i=0;i<=seg;i++){ const z=-WZ-1+(2*(WZ+1))*i/seg; const y=EAVE+(APEX-EAVE)*(1-Math.pow(z/(WZ+1),2));
    pos.push(-len/2,y,z, len/2,y,z); }
  for(let i=0;i<seg;i++){ const a=i*2; idx.push(a,a+1,a+2, a+1,a+3,a+2); }
  geo.setAttribute('position',new THREE.Float32BufferAttribute(pos,3)); geo.setIndex(idx); geo.computeVertexNormals();
  const r=new THREE.Mesh(geo,mat.roofGrey); r.castShadow=true; roofG.add(r);
  const sp=[]; for(let x=-HL/2;x<=HL/2;x+=2.5){ for(let i=0;i<seg;i++){ const z1=-WZ+2*WZ*i/seg, z2=-WZ+2*WZ*(i+1)/seg;
    const y1=EAVE-1.2+(APEX-EAVE)*(1-Math.pow(z1/WZ,2)), y2=EAVE-1.2+(APEX-EAVE)*(1-Math.pow(z2/WZ,2)); sp.push([x,y1,z1],[x,y2,z2]); } }
  for(let i=0;i<=seg;i+=2){ const z=-WZ+2*WZ*i/seg, y=EAVE-1.2+(APEX-EAVE)*(1-Math.pow(z/WZ,2)); sp.push([-HL/2,y,z],[HL/2,y,z]); }
  const spl=lines(sp,'#d8dde6',roofG); spl.userData.spaceframe=true;
  info(r);
}

// ---------- wings, front, back (revised 10 Nov from the owner's photo guide) ----------
const glassT=new THREE.MeshStandardMaterial({color:'#a9c8dc',transparent:true,opacity:.32,roughness:.1,metalness:.2,side:THREE.DoubleSide});
const tile=M('#e6e7e3',{roughness:.5}), cream=M('#ece6d2'), brick=M('#9a6b55'), rust=M('#8a4a32'), doorGrey=M('#9aa3ad'), frost=M('#f3f5f7');
function entrySign(l1,l2,l3,bg){
  return canvasTex(1024,330,async(ctx,w,h)=>{ ctx.fillStyle=bg; ctx.fillRect(0,0,w,h); ctx.fillStyle='#e4c87d'; ctx.fillRect(0,h-14,w,14);
    await drawImgFit(ctx,'joWhite',24,40,190,220,'left');
    ctx.fillStyle='#fff'; ctx.font=F(800,74); ctx.fillText(l1,240,112);
    ctx.fillStyle='rgba(255,255,255,.92)'; ctx.font=F(600,42); ctx.fillText(l2,240,186);
    ctx.fillStyle='rgba(255,255,255,.72)'; ctx.font=F(500,34); ctx.fillText(l3,240,250); });
}
function floorDecal(isP){
  return canvasTex(1024,440,async(ctx,w,h)=>{ ctx.clearRect(0,0,w,h);
    ctx.fillStyle=isP?'rgba(19,40,74,.92)':'rgba(44,76,123,.95)'; ctx.beginPath(); ctx.roundRect(8,8,w-16,h-16,36); ctx.fill();
    ctx.lineWidth=14; ctx.strokeStyle=isP?'rgba(255,255,255,.75)':'#e4c87d'; ctx.stroke();
    ctx.fillStyle='#fff'; ctx.textAlign='center'; ctx.font=F(800,isP?116:104); ctx.fillText(isP?'PANITIA':'MASUK · KELUAR',w/2,isP?250:210);
    ctx.fillStyle=isP?'rgba(255,255,255,.75)':'#e4c87d'; ctx.font=F(600,52); ctx.fillText(isP?'Committee only':'Entrance · Exit',w/2,isP?340:320); ctx.textAlign='left'; });
}
function signPlane(w,h,t,x,y,z,ry,parent){ const m=new THREE.Mesh(new THREE.PlaneGeometry(w,h),texMat(t)); m.position.set(x,y,z); m.rotation.y=ry; parent.add(m); return m; }
const DOORS={ panitia:[34,5.5], atlet:[-34,5.5], penonton:[-34,5.5] };

function wing(sgn,role){
  const g=new THREE.Group(); bld.add(g);
  const X=x=>sgn*x, T=.25, H=8;
  const wz=(x,z0,z1,y0,y1,m=mat.wallOut)=>box(T,y1-y0,z1-z0,m,X(x),y0,(z0+z1)/2,g);
  const wx=(z,x0,x1,y0,y1,m=mat.wallOut)=>box(x1-x0,y1-y0,T,m,X((x0+x1)/2),y0,z,g);
  // outer end wall with the white entrance door (2 m gap)
  wz(31.5,-10.25,4.5,0,H); wz(31.5,6.5,10.25,0,H); wz(31.5,4.5,6.5,2.5,H);
  // north wall: tall glass grid of the equipment room
  wx(-10.25,17.5,31.5,0,1.2); wx(-10.25,17.5,31.5,7,H); wx(-10.25,17.5,19.5,1.2,7); wx(-10.25,29.5,31.5,1.2,7); wx(-10.25,19.5,29.5,1.2,7,glassT);
  const gl=[]; for(let x=19.5;x<=29.5;x+=1.25) gl.push([X(x),1.2,-10.38],[X(x),7,-10.38]); for(let y=1.2;y<=7;y+=1.16) gl.push([X(19.5),y,-10.38],[X(29.5),y,-10.38]); lines(gl,'#ffffff',g);
  // south wall, partition between lobby and equipment room (glass double door near the entrance)
  wx(10.25,17.5,31.5,0,H);
  wx(1,17.5,27.5,0,H,mat.wallIn); wx(1,29.5,31.5,0,H,mat.wallIn); wx(1,27.5,29.5,2.5,H,mat.wallIn);
  // windows on the outer face: frosted panels by the door, upper row for the second floor
  [3.2,7.8].forEach(z=>box(0.06,1.7,1.5,frost,X(31.66),0.5,z,g));
  [-7.5,-4.5,-1.5,1.5,4.5,9].forEach(z=>box(0.06,1.0,2.2,mat.glass,X(31.66),5,z,g));
  // floors
  const fl=plane(14,9.25,tile,X(24.5),0.03,5.625,g); plane(14,11.25,mat.hallFloor,X(24.5),0.03,-4.625,g);
  // second floor slab (not walkable in the model) and roof
  const s1=box(14,0.2,7.6,cream,X(24.5),3.6,4.8,g), s2=box(9,0.2,1.65,cream,X(27),3.6,9.42,g), rf=box(14.6,0.4,21.1,mat.roofGrey,X(24.5),H,0,g);
  [s1,s2,rf].forEach(o=>o.userData.noWalk=true);
  // lobby: column, stepped seating on the left, stairs to the second floor at the far left
  box(0.5,3.6,0.5,cream,X(22.6),0,8.1,g);
  // stepped seating along the far (hall-side) wall, windows into the hall above it; hall door at the far right
  for(let i=0;i<3;i++) box(0.45,0.3*(i+1),3.2,frost,X(18.85-0.45*i),0,6.9,g);
  box(0.08,1.3,3,mat.glass,X(17.7),1.5,6.9,g);
  [23.5,25].forEach(x=>box(0.9,2.1,0.08,mat.dark,X(x),0,10.1,g));
  for(let i=0;i<20;i++) box(0.2,0.18*(i+1),1.4,mat.stepTread,X(21.9-0.2*i),0,9.4,g);
  lines([[X(22),0.9,8.7],[X(18),4.5,8.7],[X(22),0,8.7],[X(22),0.9,8.7],[X(20),1.8,8.7],[X(20),2.7,8.7],[X(18),3.6,8.7],[X(18),4.5,8.7]],'#3f8a55',g);
  // door frames (open gaps so walk mode goes straight through)
  const fr=(pts)=>lines(pts,'#ffffff',g);
  fr([[X(31.5),0,4.5],[X(31.5),2.5,4.5],[X(31.5),0,6.5],[X(31.5),2.5,6.5],[X(31.5),2.5,4.5],[X(31.5),2.5,6.5],[X(17.5),0,3],[X(17.5),2.5,3],[X(17.5),0,5],[X(17.5),2.5,5],[X(17.5),2.5,3],[X(17.5),2.5,5],[X(27.5),0,1],[X(27.5),2.5,1],[X(29.5),0,1],[X(29.5),2.5,1],[X(27.5),2.5,1],[X(29.5),2.5,1]]);
  // equipment room contents: stacked landing mats and trolleys
  box(2.2,2.1,5,mat.mat,X(30),0,-5.5,g); box(2.2,1.2,3,mat.matTop,X(27.3),0,-8.3,g); box(4,0.9,1,mat.red,X(21.5),0,-8.6,g); box(3,1.1,1.2,mat.dark,X(22),0,-3,g);
  info(g);
  info(fl);
  // roof overhang on white truss towers, corner drum, motorbike parking
  const xo=31.5, cw=6; const cg=new THREE.Group(); bld.add(cg);
  const cq=quad([[X(xo),9.6,-11],[X(xo),9.6,11],[X(xo+cw),6.8,11],[X(xo+cw),6.8,-11]],mat.roofGrey); cq.userData.noWalk=true; cg.add(cq);
  const tp=[]; [-10.5,-3.5,3.5,10.5].forEach(z=>{ const a=X(xo+cw-0.4), b=X(xo+cw-1.6);
    tp.push([a,0,z],[a,6.9,z],[b,0,z],[b,7.4,z],[a,0,z],[b,1.7,z],[b,1.7,z],[a,3.4,z],[a,3.4,z],[b,5.1,z],[b,5.1,z],[a,6.9,z],[b,7.4,z],[X(xo),9.4,z],[a,6.9,z],[X(xo),8,z]); });
  tp.push([X(xo+cw-0.4),6.9,-10.5],[X(xo+cw-0.4),6.9,10.5]); lines(tp,'#ffffff',cg);
  info(cg);
  const drum=cyl(1.9,H+0.4,cream,X(xo-0.3),(H+0.4)/2,-10.25,bld); info(drum);
  for(let i=0;i<8;i++) box(1.8,1.1,0.7,mat.dark,X(xo+2.4),0,-8.5+i*1.6,cg);
  plane(8,24,brick,X(xo+4),0.016,0,bld);
  // door sign + label
  const isP=role==='Panitia';
  const dec=new THREE.Mesh(new THREE.PlaneGeometry(5.6,2.4),new THREE.MeshStandardMaterial({map:floorDecal(isP),transparent:true,roughness:.8}));
  dec.rotation.set(-Math.PI/2,0,sgn>0?Math.PI/2:-Math.PI/2); dec.position.set(X(xo+3.4),0.03,5.5); dec.userData.ui=true; bld.add(dec);
  const ds=signPlane(4.2,1.35,isP?entrySign('Pintu Panitia','Khusus panitia','Committee only · no public entry','#13284a'):entrySign('Masuk & Keluar','Atlet · Ofisial · Tamu · Penonton','Entrance & exit · athletes, officials, guests, spectators','#2c4c7b'),X(xo+0.2),3.3,5.5,sgn>0?Math.PI/2:-Math.PI/2,bld);
  info(ds);
  addLabel(isP?'Pintu Panitia · khusus panitia|Committee entrance only':'Pintu masuk & keluar umum|Public entrance & exit · athletes, officials, guests, spectators',[X(xo+1),5.4,5.5],isP?'door com':'door pub',true);
  return g;
}
const annexE=wing(1,'Panitia');
const annexW=wing(-1,'Umum');

// FRONT (north): yellow portico with the "Gymnasium" lettering, IMG_5400 / IMG_5401
{
  const g=new THREE.Group(); bld.add(g); const z0=-WZ, z1=-WZ-7;
  box(26,2.2,7,mat.yellow,0,0,(z0+z1)/2,g); box(26,2.4,7,M('#c9cdd3'),0,2.2,(z0+z1)/2,g);
  [-10.5,-7,7,10.5].forEach(x=>box(2.6,1.5,0.08,frost,x,0.6,z1-0.05,g));
  box(3.4,2.6,0.1,mat.glass,0,0,z1-0.06,g);
  [-6.6,-2.3,2.3,6.6].forEach(x=>box(0.55,4.4,0.55,mat.yellow,x,0,z1-2.6,g));
  box(14.2,0.45,3.2,mat.yellow,0,4.4,z1-1.4,g);
  const fz=quad([[-13.4,4.9,z1-3.1],[13.4,4.9,z1-3.1],[13.4,7.6,z1+1.5],[-13.4,7.6,z1+1.5]],mat.roofGrey); fz.userData.noWalk=true; g.add(fz);
  const cap=quad([[-13.4,7.6,z1+1.5],[13.4,7.6,z1+1.5],[13.4,7.9,z0],[-13.4,7.9,z0]],mat.roofGrey); cap.userData.noWalk=true; g.add(cap);
  const s=new THREE.Mesh(new THREE.PlaneGeometry(9.5,1.2),texMat(texSign)); s.position.set(0,5.75,z1-3.16); s.rotation.y=Math.PI; g.add(s);
  plane(30,9,brick,0,0.016,z1-5.5,bld);
  for(let i=0;i<4;i++) box(0.7,1.1,1.8,mat.dark,-11+i*1.5,0,z1-1.6,g);
  info(g);
  const ds=signPlane(4,1.29,entrySign('Kantor DISPORA','Bukan pintu masuk','Office · not an entrance','#5f6873'),0,3.7,z1-2.9,Math.PI,bld);
  // rope barrier in front of the closed middle door
  [-2.4,0,2.4].forEach(x=>{ cyl(0.05,1,mat.steel,x,0.5,z1-1.4,g); box(0.36,0.05,0.36,mat.dark,x,0,z1-1.4,g); });
  box(4.8,0.06,0.04,mat.red,0,0.9,z1-1.4,g);
  info(ds);
  addLabel('Kantor DISPORA · bukan pintu masuk|DISPORA office · not an entrance',[0,8.6,z1-2],'door no',true);
}
// BACK (south): low service block facing the road, IMG_5414
{
  const g=new THREE.Group(); bld.add(g); const z0=WZ, z1=WZ+5;
  box(24,4.2,5,frost,0,0,(z0+z1)/2,g); const rs=box(25.2,0.3,6.4,M('#b8b6ae'),0,4.2,(z0+z1)/2+0.4,g); rs.userData.noWalk=true;
  [-2.6,1.4].forEach(x=>{ box(1.9,2.5,0.1,doorGrey,x,0.3,z1+0.05,g); });
  [-10.2,-9.4,-7.6].forEach((x,i)=>{ cyl(0.17,3.3-i*0.3,rust,x,(3.3-i*0.3)/2,z1+0.35,g); });
  [4,6.5,9].forEach(x=>box(0.6,0.4,0.08,M('#6d747c'),x,3.2,z1+0.05,g));
  box(24,0.5,1.2,M('#b8b6ae'),0,0,z1+0.6,g);
  plane(64,2.6,brick,0,0.016,z1+5.2,bld);
  info(g);
  addLabel('Belakang gedung · sisi jalan|Rear of building · road side',[0,5.6,z1],'',true);
}

// ---------- wayfinding totems (inverted T) ----------
const TOTEM_ROWS=[['atlet','Atlet · Ofisial · Tamu','Athletes · Officials · Guests','#2c4c7b'],['penonton','Penonton','Spectators','#2c4c7b'],['panitia','Panitia','Committee only','#13284a']];
function totemTex(px,pz,nx,nz){
  return canvasTex(400,1040,async(ctx,w,h)=>{
    ctx.fillStyle='#ffffff'; ctx.fillRect(0,0,w,h); ctx.fillStyle='#13284a'; ctx.fillRect(0,0,w,190); ctx.fillStyle='#e4c87d'; ctx.fillRect(0,190,w,10);
    await drawImgFit(ctx,'joWhite',70,18,260,155);
    TOTEM_ROWS.forEach(([k,t1,t2,col],i)=>{
      const y=215+i*272; const [dx,dz]=DOORS[k]; const vx=dx-px, vz=dz-pz; const fx=-nx, fz=-nz; const f=vx*fx+vz*fz, s=vx*(-fz)+vz*fx;
      const ang=Math.round(Math.atan2(s,f)/(Math.PI/4))*(Math.PI/4);
      ctx.fillStyle=col; ctx.beginPath(); ctx.arc(w/2,y+78,66,0,Math.PI*2); ctx.fill();
      ctx.save(); ctx.translate(w/2,y+78); ctx.rotate(ang); ctx.strokeStyle='#fff'; ctx.lineWidth=15; ctx.lineCap='round'; ctx.lineJoin='round';
      ctx.beginPath(); ctx.moveTo(0,36); ctx.lineTo(0,-36); ctx.moveTo(-26,-10); ctx.lineTo(0,-38); ctx.lineTo(26,-10); ctx.stroke(); ctx.restore();
      ctx.textAlign='center'; ctx.fillStyle='#13284a'; ctx.font=F(800,t1.length>12?31:44); ctx.fillText(t1,w/2,y+190);
      ctx.fillStyle='#5b6b88'; ctx.font=F(500,24); ctx.fillText(t2,w/2,y+226);
      const m=Math.round(Math.hypot(vx,vz)/5)*5; ctx.fillStyle='#8a6a1f'; ctx.font=F(700,24); ctx.fillText('± '+m+' m',w/2,y+256);
      ctx.textAlign='left';
    });
  });
}
const totems=new THREE.Group(); bld.add(totems);
[[0,-33.5,Math.PI],[27,-24,Math.PI*0.75],[-27,-24,-Math.PI*0.75],[38.5,-13,Math.PI],[-38.5,-13,Math.PI],[25,27.5,Math.PI/4],[-25,27.5,-Math.PI/4],[0,29.5,0]].forEach(([x,z,ry],i)=>{
  const t=new THREE.Group(); t.position.set(x,0,z); t.rotation.y=ry; totems.add(t);
  box(1.9,0.16,0.7,mat.navy,0,0,0,t); box(1.05,2.75,0.14,mat.navy,0,0.16,0,t); box(1.05,0.08,0.16,mat.yellow,0,2.91,0,t);
  const nx=Math.sin(ry), nz=Math.cos(ry);
  const a=new THREE.Mesh(new THREE.PlaneGeometry(0.95,2.47),texMat(totemTex(x,z,nx,nz))); a.position.set(0,1.5,0.075); t.add(a);
  const b=new THREE.Mesh(new THREE.PlaneGeometry(0.95,2.47),texMat(totemTex(x,z,-nx,-nz))); b.position.set(0,1.5,-0.075); b.rotation.y=Math.PI; t.add(b);
  info(t);
});
// outdoor bits (building frame)
const pv=plane(10.6,7.07,new THREE.MeshStandardMaterial({color:'#bdb6aa'}),HL/2+10,0.02,WZ+14,bld);
info(pv);
const tank=cyl(1.4,2.6,M('#9b6a3e',{metalness:.4}),-HL/2-4,1.8,-WZ-9,bld);
info(tank);
[[HL/2+3,WZ+8],[-HL/2-6,-WZ-6],[0,WZ+9]].forEach(([x,z])=>{ const h=box(0.6,1.1,0.4,mat.red,x,0,z,bld); info(h); });

/* ---------------- equipment builders ---------------- */
const phaseGroups={};
PHASES.forEach(p=>{ phaseGroups[p.id]=new THREE.Group(); bld.add(phaseGroups[p.id]); });
const permanent=new THREE.Group(); bld.add(permanent);
const W=(px)=>px-17.5, Z=(py)=>py-12.5; // PDF metres -> world

function floorArea(g,w,d,inner,border,x,z){
  const o=new THREE.Group(); g.add(o);
  box(w,0.05,d,border,x,0.03,z,o); box(w-2,0.06,d-2,inner,x,0.03,z,o); return o;
}
function judges(g,len,x,z,rot=0){
  const o=new THREE.Group(); o.position.set(x,0,z); o.rotation.y=rot; g.add(o);
  box(len,0.75,0.8,mat.white,0,0,0,o);
  const s=new THREE.Mesh(new THREE.PlaneGeometry(len,0.7),texMat(texSkirt)); s.position.set(0,0.38,0.41); o.add(s);
  for(let i=0;i<Math.max(2,Math.round(len/1.2));i++) box(0.45,0.9,0.45,mat.navy,-len/2+0.6+i*1.2,0,-0.75,o);
  return info(o);
}
function matBlock(g,w,d,h,x,z,m=mat.mat){ return box(w,h,d,m,x,0,z,g); }
function vault(g){
  const o=new THREE.Group(); g.add(o);
  box(25,0.03,1,mat.runway,W(13),0.02,Z(3.3),o);
  box(0.9,0.2,1.2,mat.white,W(26.2),0,Z(3.3),o);
  cyl(0.12,1.2,mat.steel,W(27),0.6,Z(3.3),o); box(1.2,0.15,0.95,mat.leather,W(27),1.2,Z(3.3),o);
  matBlock(o,6,2.6,0.3,W(30.8),Z(3.3));
  info(o);
  addLabel('Lompat|Vault',[W(27),2.4,Z(3.3)]);
}
function unevenBars(g){
  const o=new THREE.Group(); o.position.set(W(30.7),0,Z(9.3)); g.add(o);
  box(2.6,0.25,9,mat.pit,0,0,0,o);
  [[-0.9,1.7],[0.9,2.5]].forEach(([z,h])=>{ cyl(0.05,h,mat.steel,-1.2,h/2,z,o); cyl(0.05,h,mat.steel,1.2,h/2,z,o); cyl(0.025,2.4,mat.white,0,h,z,o,0,Math.PI/2); });
  lines([[-1.2,2.5,0.9],[-3,0,2.8],[1.2,2.5,0.9],[3,0,2.8],[-1.2,1.7,-0.9],[-3,0,-2.8],[1.2,1.7,-0.9],[3,0,-2.8]],'#c8473a',o);
  info(o);
  addLabel('Palang bertingkat|Uneven bars',[W(30.7),3.4,Z(9.3)]);
}
function rings(g){
  const o=new THREE.Group(); o.position.set(W(31),0,Z(18.5)); g.add(o);
  [-1.6,1.6].forEach(x=>{ lines([[x,5.75,0],[x-1.2,0,-2.2],[x,5.75,0],[x-1.2,0,2.2],[x,5.75,0],[x+0.8,0,-2.2],[x,5.75,0],[x+0.8,0,2.2]],'#c8473a',o); });
  cyl(0.06,3.2,mat.steel,0,5.75,0,o,0,Math.PI/2);
  [-0.25,0.25].forEach(x=>{ lines([[x,5.75,0],[x,2.8,0]],'#555',o); const r=new THREE.Mesh(new THREE.TorusGeometry(0.09,0.015,6,16),mat.leather); r.position.set(x,2.75,0); o.add(r); });
  box(2.2,0.25,6,mat.pit,0,0,0,o);
  info(o);
  addLabel('Gelang-gelang|Rings',[W(31),6.4,Z(18.5)]);
}
function highBar(g){
  const o=new THREE.Group(); g.add(o);
  box(12.6,0.25,2,mat.pit,W(7.5),0,Z(21.7),o);
  const x=W(7.5); [-1.2,1.2].forEach(dz=>cyl(0.05,2.8,mat.steel,x,1.4,Z(21.7)+dz,o));
  cyl(0.028,2.4,mat.white,x,2.8,Z(21.7),o,Math.PI/2,0);
  lines([[x,2.8,Z(21.7)-1.2],[x-2.6,0,Z(21.7)-2.6],[x,2.8,Z(21.7)-1.2],[x+2.6,0,Z(21.7)-2.6],[x,2.8,Z(21.7)+1.2],[x-2.6,0,Z(21.7)+2.6],[x,2.8,Z(21.7)+1.2],[x+2.6,0,Z(21.7)+2.6]],'#c8473a',o);
  info(o);
  addLabel('Palang tunggal|High bar',[x,3.6,Z(21.7)]);
}
function beam(g,x,z){
  const o=new THREE.Group(); o.position.set(x,0,z); g.add(o);
  box(10.5,0.2,3,mat.mat,0,0,0,o);
  [-1.8,1.8].forEach(dx=>{ box(0.12,1.05,0.4,mat.steel,dx,0.2,0,o); });
  box(5,0.16,0.1,mat.beam,0,1.25,0,o);
  info(o);
  addLabel('Balok|Beam',[x,2,z]);
}
function parallelBars(g,x,z,mw=8.8,md=4){
  const o=new THREE.Group(); o.position.set(x,0,z); g.add(o);
  box(mw,0.2,md,mat.mat,0,0,0,o);
  [-0.24,0.24].forEach(dz=>{ [-1,1].forEach(dx=>cyl(0.04,1.8,mat.steel,dx,1.1,dz,o)); cyl(0.025,3.5,mat.beam,0,2.0,dz,o,0,Math.PI/2); });
  info(o);
  addLabel('Palang sejajar|Parallel bars',[x,2.8,z]);
}
function pommel(g,x,z,mw=5,md=4){
  const o=new THREE.Group(); o.position.set(x,0,z); g.add(o);
  box(mw,0.2,md,mat.mat,0,0,0,o);
  [-0.5,0.5].forEach(dx=>box(0.12,0.85,0.12,mat.steel,dx,0.2,0,o));
  box(1.6,0.3,0.35,mat.leather,0,1.0,0,o);
  info(o);
  addLabel('Kuda-kuda pelana|Pommel horse',[x,2,z]);
}
function medis(g,x,z){
  const o=new THREE.Group(); o.position.set(x,0,z); g.add(o);
  box(2,0.75,0.8,mat.white,0,0,0,o);
  const s=panel(1.6,0.8,texMedis,0,1.2,-0.3,0,o);
  box(2,0.5,0.7,mat.red,0,0,1.2,o);
  info(o);
  addLabel('Medis|Medical',[x,2.4,z]);
}
function divider(g,x,z1,z2){ const o=box(0.1,0.9,z2-z1,mat.navy,x,0,(z1+z2)/2,g); return info(o); }
function kissCry(g,x,z){
  const o=new THREE.Group(); o.position.set(x,0,z); g.add(o);
  panel(3,1.5,texKC,0,0.5,-0.6,0,o); box(2.4,0.45,0.5,mat.navy,0,0,0.2,o);
  info(o);
  addLabel('Kiss & Cry',[x,2.6,z]);
}

// permanent pits & fixed apparatus (present in every phase)
unevenBars(permanent); rings(permanent); highBar(permanent);

// --- artistic ---
curOwner='art';
{ const g=phaseGroups.art;
  const f=floorArea(g,14,14,mat.artFloor,mat.artBorder,W(20.6),Z(12.4));
  info(f);
  addLabel('Lantai senam 14 × 14 m|Floor exercise',[W(20.6),0.8,Z(12.4)]);
  vault(g); beam(g,W(19.5),Z(21.9)); parallelBars(g,W(5.9),Z(8.2)); pommel(g,W(5.6),Z(15.2)); medis(g,-16.2,7.4);
  judges(g,4.5,-11.6,-1,Math.PI); judges(g,4.5,-11.9,5.8,Math.PI); judges(g,4.5,2,11.6,Math.PI);
  judges(g,6,-5.2,-0.1,Math.PI/2); judges(g,4.5,7.6,-11.6,0);
  judges(g,4,16.6,-1,-Math.PI/2); judges(g,4,16.6,10.6,-Math.PI/2);
  podium(g,-15.6,0,Math.PI/2);
}
// --- rhythmic ---
curOwner='rg';
{ const g=phaseGroups.rg;
  const f=floorArea(g,14,14,mat.rgCarpet,mat.rgBorder,W(10.2),Z(11.6));
  info(f);
  addLabel('Karpet ritmik 14 × 14 m|Rhythmic carpet',[W(10.2),0.8,Z(11.6)]);
  const w=floorArea(g,7.8,13.5,mat.warm,mat.rgBorder,W(23.9),Z(11.3));
  info(w);
  addLabel('Pemanasan ritmik|Rhythmic warm-up',[W(23.9),0.8,Z(11.3)]);
  divider(g,W(18.2),Z(4),Z(19)); judges(g,12,W(1.1),Z(11.6),Math.PI/2);
  addLabel('Meja juri|Judges',[W(1.1),1.5,Z(11.6)]);
  kissCry(g,-15.3,-10.4); podium(g,-10,-10.4,0);
}
// --- aerobic ---
curOwner='aer';
{ const g=phaseGroups.aer;
  const f=floorArea(g,12,12,mat.aerFloor,mat.aerBorder,W(10.2),Z(11.6));
  info(f);
  addLabel('Lantai aerobik 10 × 10 m|Aerobic floor',[W(10.2),0.8,Z(11.6)]);
  const w=floorArea(g,7.8,13,mat.warmAer,mat.aerBorder,W(23.9),Z(11.3));
  info(w);
  addLabel('Pemanasan aerobik|Aerobic warm-up',[W(23.9),0.8,Z(11.3)]);
  divider(g,W(18.1),Z(4),Z(19)); judges(g,12,W(2.6),Z(11),Math.PI/2);
  addLabel('Meja juri|Judges',[W(2.6),1.5,Z(11)]);
  kissCry(g,-15.3,-10.4); podium(g,-10,-10.4,0);
}
curOwner=null;

/* ---------------- UI text (follows the site's ID/EN choice) ---------------- */
const TX={
  id:{roof:'Atap',walls:'Dinding',lbl:'Label',reset:'Reset kamera',fs:'Layar penuh',fsx:'Keluar layar penuh',
      hint:'Seret untuk memutar · klik kanan atau Shift + seret untuk menggeser · gulir untuk zoom · W A S D untuk bergerak',
      situs:'Situs',denah:'Denah',tribun:'Dari tribun',pintu:'Pintu masuk',hall:'Dalam aula'},
  en:{roof:'Roof',walls:'Walls',lbl:'Labels',reset:'Reset camera',fs:'Full screen',fsx:'Exit full screen',
      hint:'Drag to orbit · right-click or Shift + drag to pan · scroll to zoom · W A S D to move',
      situs:'Site',denah:'Plan',tribun:'From the stands',pintu:'Entrance',hall:'Inside the hall'}
}[L10N]||{};

/* ---------------- state ---------------- */
let phase='art', showRoof=true, showWalls=true, showLabels=true;
function setPhase(id){
  phase=id;
  for(const k in phaseGroups) phaseGroups[k].visible=(k===id);
  document.querySelectorAll('#phases button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.id===id)));
  try{ history.replaceState(null,'','#'+id);}catch(e){}
}
const phasesEl=document.getElementById('phases');
PHASES.forEach(p=>{ const b=document.createElement('button'); b.type='button'; b.dataset.id=p.id; b.innerHTML=`${p.tab[L10N]||p.tab.id}<span class="d">${p.d[L10N]||p.d.id}</span>`; b.onclick=()=>setPhase(p.id); phasesEl.appendChild(b); });

const VIEWS={
  situs:{pos:[95,70,110],tgt:[0,4,0],roof:true,walls:true},
  denah:{pos:[0,62,0.5],tgt:[0,0,0],roof:false,walls:true},
  tribun:{pos:[4,8.5,16.5],tgt:[0,1,-3],roof:true,walls:true},
  pintu:{pos:[-50,4.6,15],tgt:[-32,2.4,5.5],roof:true,walls:true},
};
// extra framings used by the entrance legend (no buttons)
const SPOTS={
  pub:{pos:[-50,4.6,15],tgt:[-32,2.4,5.5],roof:true,walls:true},
  com:{pos:[50,4.6,15],tgt:[32,2.4,5.5],roof:true,walls:true},
  no:{pos:[10,7,-48],tgt:[0,3,-25],roof:true,walls:true},
};
let anim=null;
function fly(v){
  setRoof(v.roof); setWalls(v.walls);
  anim={from:camera.position.clone(),to:new THREE.Vector3(...v.pos),tf:controls.target.clone(),tt:new THREE.Vector3(...v.tgt),t:0,t0:performance.now()};
  if(matchMedia('(prefers-reduced-motion: reduce)').matches) anim.t=1;
}
function goView(id){
  fly(VIEWS[id]);
  document.querySelectorAll('#views button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.id===id)));
}
const viewsEl=document.getElementById('views');
Object.keys(VIEWS).forEach(id=>{ const b=document.createElement('button'); b.type='button'; b.dataset.id=id; b.textContent=TX[id]; b.onclick=()=>goView(id); viewsEl.appendChild(b); });
document.querySelectorAll('[data-spot]').forEach(b=>b.addEventListener('click',()=>{
  fly(SPOTS[b.dataset.spot]); document.querySelectorAll('#views button').forEach(x=>x.setAttribute('aria-pressed','false'));
}));

const togEl=document.getElementById('toggles');
const TOG={roof:()=>setRoof(!showRoof),walls:()=>setWalls(!showWalls),lbl:()=>{showLabels=!showLabels;syncTog();}};
Object.entries(TOG).forEach(([id,fn])=>{ const b=document.createElement('button'); b.type='button'; b.dataset.id=id; b.textContent=TX[id]; b.onclick=fn; togEl.appendChild(b); });
function syncTog(){
  const st={roof:showRoof,walls:showWalls,lbl:showLabels};
  togEl.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(!!st[b.dataset.id])));
}
function setRoof(v){ showRoof=v; roofG.visible=v; syncTog(); }
function setWalls(v){ showWalls=v; walls.s.visible=v; walls.n.visible=v; endMeshes.forEach(m=>m.visible=v); syncTog(); }
document.getElementById('hint').textContent=TX.hint;

const ray=new THREE.Raycaster(), ptr=new THREE.Vector2();

/* ---------------- label projection ---------------- */
const tmp=new THREE.Vector3();
site.updateMatrixWorld(true);
const occRay=new THREE.Raycaster(); let occT=0; const occHidden=new Set();
function updateOcclusion(){
  occHidden.clear();
  if(camera.position.y>=25) return;
  const list=[]; scene.traverse(o=>{ if(o.isMesh&&o.material&&o.material.visible!==false&&visibleDeep(o)) list.push(o); });
  const w=new THREE.Vector3(), d=new THREE.Vector3();
  for(const L of labels){
    w.copy(L.pos); if(L.siteLocal) w.applyMatrix4(site.matrixWorld);
    d.copy(w).sub(camera.position); const dist=d.length(); d.normalize();
    occRay.set(camera.position,d); occRay.far=dist-0.6;
    if(occRay.intersectObjects(list,false).length) occHidden.add(L);
  }
}
function updateLabels(){
  const r=renderer.domElement.getBoundingClientRect();
  const nowT=performance.now(); if(nowT-occT>180){ occT=nowT; updateOcclusion(); }
  const cp=camera.position; const inside=Math.abs(cp.x)<17.5&&Math.abs(cp.z)<18.5&&cp.y<14;
  for(const L of labels){
    let show=showLabels;
    if(L.owner && L.owner!==phase) show=false;
    if(L.siteLocal&&inside) show=false;
    if(!inside&&showRoof&&!L.far&&!L.siteLocal&&Math.abs(L.pos.x)<17.6&&Math.abs(L.pos.z)<18.6&&cp.y<25) show=false;
    if(!show){ L.el.style.display='none'; continue; }
    if(occHidden.has(L)){ L.el.style.display='none'; L.el.dataset.occ='1'; continue; }
    tmp.copy(L.pos); if(L.siteLocal) tmp.applyMatrix4(site.matrixWorld);
    const dist=camera.position.distanceTo(tmp);
    tmp.project(camera);
    if(tmp.z>1||tmp.z<-1||Math.abs(tmp.x)>1.1||Math.abs(tmp.y)>1.1||(!L.siteLocal&&dist>(L.far?260:95))||(L.siteLocal&&dist<40)){ L.el.style.display='none'; continue; }
    L.el.style.display='block';
    L.el.style.left=((tmp.x+1)/2*r.width)+'px'; L.el.style.top=((1-tmp.y)/2*r.height)+'px';
  }
}

/* ---------------- loop ---------------- */
function resize(){ const w=stage.clientWidth,h=stage.clientHeight; renderer.setSize(w,h,false); camera.aspect=w/h; camera.updateProjectionMatrix(); }
new ResizeObserver(resize).observe(stage); resize();
const needle=document.getElementById('needle');
let lastT=performance.now();
function tick(){
  requestAnimationFrame(tick);
  const now=performance.now(), dt=Math.min(0.1,(now-lastT)/1000); lastT=now;
  if(anim){ anim.t=Math.max(anim.t,Math.min(1,(performance.now()-anim.t0)/700)); const k=1-Math.pow(1-anim.t,3);
    camera.position.lerpVectors(anim.from,anim.to,k); controls.target.lerpVectors(anim.tf,anim.tt,k); if(anim.t>=1) anim=null; }
  orbitKeys(dt); controls.update();
  // compass: map north = site -z
  const north=new THREE.Vector3(0,0,-1).applyAxisAngle(new THREE.Vector3(0,1,0),site.rotation.y);
  const az=controls.getAzimuthalAngle(); const ux=-Math.sin(az), uz=-Math.cos(az); const rx=-uz, rz=ux;
  const ang=Math.atan2(north.x*rx+north.z*rz, north.x*ux+north.z*uz);
  needle.setAttribute('transform',`rotate(${THREE.MathUtils.radToDeg(ang)} 15 15)`);
  renderer.render(scene,camera); updateLabels();
}

/* ---------------- zoom (trackpad pinch + scroll, toward cursor) ---------------- */
const groundPlane=new THREE.Plane(new THREE.Vector3(0,1,0),0);
function visibleDeep(o){ let n=o; while(n){ if(!n.visible) return false; n=n.parent; } return true; }
function zoomAt(scale,cx,cy){
  const r=renderer.domElement.getBoundingClientRect();
  let pivot=controls.target.clone();
  if(cx!==undefined){
    ptr.set(((cx-r.left)/r.width)*2-1,-((cy-r.top)/r.height)*2+1); ray.setFromCamera(ptr,camera);
    const hit=ray.intersectObjects(pickables.filter(visibleDeep),false)[0];
    if(hit) pivot=hit.point.clone(); else { const p=new THREE.Vector3(); if(ray.ray.intersectPlane(groundPlane,p)) pivot=p; }
  }
  const dist=camera.position.distanceTo(controls.target);
  if(scale<1 && dist*scale<2.5){ // dolly through: push target forward instead of stalling
    const fwd=new THREE.Vector3(); camera.getWorldDirection(fwd);
    const step=fwd.multiplyScalar((1-scale)*12); camera.position.add(step); controls.target.add(step); return;
  }
  if(scale>1 && dist*scale>320) return;
  camera.position.sub(pivot).multiplyScalar(scale).add(pivot);
  controls.target.sub(pivot).multiplyScalar(scale).add(pivot);
}
stage.addEventListener('wheel',e=>{
  if(e.target!==renderer.domElement) return;
  e.preventDefault(); e.stopPropagation();
  let dy=e.deltaY; if(e.deltaMode===1) dy*=16; else if(e.deltaMode===2) dy*=400;
  anim=null;
  const k=e.ctrlKey?0.022:0.0028; // pinch arrives as ctrl+wheel with small deltas
  zoomAt(THREE.MathUtils.clamp(Math.exp(dy*k),0.55,1.8),e.clientX,e.clientY);
},{capture:true,passive:false});
controls.zoomSpeed=1.6;
controls.keyPanSpeed=0;
document.getElementById('zIn').onclick=()=>zoomAt(0.65);
document.getElementById('zOut').onclick=()=>zoomAt(1.5);

/* ---------------- reset + keyboard move ---------------- */
function resetCamera(){ camera.fov=45; camera.updateProjectionMatrix(); camera.up.set(0,1,0); goView('situs'); }
const resetBtn=document.getElementById('resetBtn'); resetBtn.textContent=TX.reset; resetBtn.onclick=resetCamera;
const okeys={};
window.addEventListener('keydown',e=>{ if(e.metaKey||e.ctrlKey||e.altKey) return; const k=e.key.toLowerCase();
  if(['w','a','s','d','q','e','arrowup','arrowdown','arrowleft','arrowright','shift'].includes(k)){ okeys[k]=true; if(k!=='shift') e.preventDefault(); }
  if(k==='0'||k==='home'){ resetCamera(); } });
window.addEventListener('keyup',e=>{ okeys[e.key.toLowerCase()]=false; });
window.addEventListener('blur',()=>{ for(const k in okeys) okeys[k]=false; });
function orbitKeys(dt){
  const f=(okeys.w||okeys.arrowup?1:0)-(okeys.s||okeys.arrowdown?1:0), s=(okeys.d||okeys.arrowright?1:0)-(okeys.a||okeys.arrowleft?1:0), v=(okeys.e?1:0)-(okeys.q?1:0);
  if(!f&&!s&&!v) return; anim=null;
  const dist=camera.position.distanceTo(controls.target); const sp=Math.max(3,dist*0.7)*(okeys.shift?2.5:1)*dt;
  const az=controls.getAzimuthalAngle(); const fx=-Math.sin(az), fz=-Math.cos(az);
  const d=new THREE.Vector3((fx*f-fz*s)*sp,v*sp,(fz*f+fx*s)*sp);
  if(controls.target.y+d.y<0) d.y=-controls.target.y;
  camera.position.add(d); controls.target.add(d);
}
// Shift + left drag pans (OrbitControls already pans on right drag)
renderer.domElement.addEventListener('pointerdown',e=>{ controls.mouseButtons.LEFT=e.shiftKey?THREE.MOUSE.PAN:THREE.MOUSE.ROTATE; },true);

/* ---------------- full screen ---------------- */
const fsBtn=document.getElementById('fsBtn'); fsBtn.textContent=TX.fs;
function setFs(v){
  document.body.classList.toggle('fs',v); fsBtn.setAttribute('aria-pressed',String(v)); fsBtn.textContent=v?TX.fsx:TX.fs;
  try{
    if(v && !document.fullscreenElement && document.documentElement.requestFullscreen){ const pr=document.documentElement.requestFullscreen(); pr&&pr.catch&&pr.catch(()=>{}); }
    if(!v && document.fullscreenElement && document.exitFullscreen){ const pr=document.exitFullscreen(); pr&&pr.catch&&pr.catch(()=>{}); }
  }catch(e){}
}
fsBtn.onclick=()=>setFs(!document.body.classList.contains('fs'));
document.addEventListener('fullscreenchange',()=>{ if(!document.fullscreenElement && document.body.classList.contains('fs')) setFs(false); });
window.addEventListener('keydown',e=>{ if(e.key==='Escape' && document.body.classList.contains('fs')) setFs(false); });

const start=(location.hash||'').slice(1);
setPhase(PHASES.some(p=>p.id===start)?start:'art');
camera.position.set(95,70,110); controls.target.set(0,4,0);
goView('situs'); anim.t=1;
syncTog();
document.getElementById('loading').remove();
tick();
window.addEventListener('hashchange',()=>{const h=location.hash.slice(1); if(PHASES.some(p=>p.id===h)&&h!==phase) setPhase(h);});
