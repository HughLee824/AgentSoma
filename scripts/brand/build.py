#!/usr/bin/env python3
"""Rebuild the selected A swipe logo. Python standard library only.
Usage: python build.py [--out DIRECTORY]. Font outlines are retained in reference/.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2] / "assets/brand/iphone-use-final"
def n(v):return f'{v:.9f}'.rstrip('0').rstrip('.') or '0'
def xy(p):return ' '.join(n(v) for v in p)
def polar(center,r,angle):return [center[0]+r*math.cos(angle),center[1]+r*math.sin(angle)]
def rect(o):
    x,y,w,h,r=[o[k] for k in ('x','y','width','height','radius')]
    assert min(w,h)>=2*r
    return f'M{x+r} {y} H{x+w-r} A{r} {r} 0 0 1 {x+w} {y+r} V{y+h-r} A{r} {r} 0 0 1 {x+w-r} {y+h} H{x+r} A{r} {r} 0 0 1 {x} {y+h-r} V{y+r} A{r} {r} 0 0 1 {x+r} {y} Z'
def phone_outline(o):
    """Frozen native continuous-corner profile; only the logo's non-overlapping case."""
    x,y,w,h,r=[o[k] for k in ('x','y','width','height','radius')]
    corner=o['corner'];extent=corner['extent'];curves=corner['cubics']
    assert corner['style']=='continuous' and r>0 and min(w,h)>2*r*extent
    assert len(curves)==3 and all(len(curve)==3 for curve in curves)
    transforms=[lambda u,v:[x+w-r*u,y+r*v],lambda u,v:[x+w-r*v,y+h-r*u],
                lambda u,v:[x+r*u,y+h-r*v],lambda u,v:[x+r*v,y+r*u]]
    commands=[];segments=[]
    for transform in transforms:
        start=transform(extent,0)
        commands.append(('M' if not commands else 'L')+xy(start))
        for curve in curves:
            points=[transform(*point) for point in curve]
            commands.append('C'+' '.join(xy(point) for point in points))
            segments.append([start,*points]);start=points[-1]
    return ' '.join(commands)+' Z',segments
def document(body,w,h,title):return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{title}">{body}</svg>\n'
def label(x,y,t,size=17,color='#6B6B65',anchor='start'):return f'<text x="{x}" y="{y}" font-family="Helvetica,Arial,sans-serif" font-size="{size}" fill="{color}" text-anchor="{anchor}">{t}</text>'

def geometry(p):
    s=p['swipe'];c=s['center'];r=s['radius'];half=s['width']/2
    a,b=math.radians(s['start_degrees']),math.radians(s['end_degrees'])
    assert 0<b-a<math.pi and r>half
    start,end=polar(c,r,a),polar(c,r,b)
    outer_start,outer_end=polar(c,r+half,a),polar(c,r+half,b)
    inner_start,inner_end=polar(c,r-half,a),polar(c,r-half,b)
    arc=(f'M{xy(outer_start)} A{n(r+half)} {n(r+half)} 0 0 1 {xy(outer_end)} '
         f'A{n(half)} {n(half)} 0 0 1 {xy(inner_end)} '
         f'A{n(r-half)} {n(r-half)} 0 0 0 {xy(inner_start)} '
         f'A{n(half)} {n(half)} 0 0 1 {xy(outer_start)} Z')
    outline,curves=phone_outline(p['phone'])
    pieces=[outline,rect(p['speaker']),arc]
    return {'path':' '.join(pieces),'pieces':pieces,'phone_cubics':curves,'arc_start':start,'arc_end':end,'cap_centers':[start,end]}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--out',type=Path,default=ROOT);args=parser.parse_args();out=args.out;out.mkdir(parents=True,exist_ok=True)
    p=json.loads((ROOT/'geometry.json').read_text());g=geometry(p);ink=p['ink'];white=p['inverse']
    def mark(color=ink,transform=''):return f'<path d="{g["path"]}" fill="{color}" fill-rule="evenodd" transform="{transform}"/>'
    source_word=ET.parse(ROOT/'reference/approved-wordmark.svg').getroot()
    letters=''.join(f'<path d="{e.attrib["d"]}"/>' for e in source_word[1])
    def word(x,y,color=ink):return f'<g fill="{color}" transform="translate({x} {y})">{letters}</g>'
    files={'mark.svg':document(mark(),160,160,'iphone-use swipe logo'),
           'inverse.svg':document(mark(white),160,160,'iphone-use swipe inverse'),
           'wordmark.svg':document(mark(ink,'translate(8 8) scale(.6)')+word(116,72),350,112,'iphone-use'),
           'wordmark-inverse.svg':document(mark(white,'translate(8 8) scale(.6)')+word(116,72,white),350,112,'iphone-use')}
    preview='<rect width="1400" height="960" fill="#F5F5F2"/>'
    preview+=label(64,62,'iphone-use',20,ink)+label(1336,62,'IDENTITY / MASTER',13,anchor='end')
    preview+=mark(ink,'translate(146 104) scale(3.2)')
    preview+='<g transform="translate(734 327) scale(1.6)">'+word(0,0)+'</g>'
    preview+=label(734,390,'A simple gesture. A real iPhone.',24,ink)
    preview+=label(734,434,'Phone silhouette + continuous swipe',17)
    preview+='<path d="M64 666 H1336" stroke="#D8D8D0"/>'
    preview+='<rect x="64" y="710" width="390" height="184" rx="18" fill="#171717"/>'+mark(white,'translate(163 706) scale(1.2)')
    preview+='<rect x="480" y="710" width="390" height="184" rx="18" fill="#DDE8E1"/>'+mark(ink,'translate(579 706) scale(1.2)')
    preview+=label(934,742,'DIGITAL SIZES',13)
    for i,size in enumerate([24,32,48,64]):
        x=945+i*98
        preview+=mark(ink,f'translate({x} {775+(64-size)/2}) scale({size/160})')+label(x+size/2,875,str(size)+' px',12,anchor='middle')
    files['preview.svg']=document(preview,1400,960,'iphone-use final identity')
    o=p['phone'];s=p['swipe'];sp=p['speaker'];unit=p['module']
    sheet='<rect width="1500" height="1080" fill="#FAFAF7"/>'
    sheet+='<defs><pattern id="hatch" width="2" height="2" patternUnits="userSpaceOnUse" patternTransform="rotate(35)"><rect width="2" height="2" fill="#E8E8E3"/><path d="M0 0 V2" stroke="#99998F" stroke-width=".25"/></pattern></defs>'
    sheet+=label(64,65,'iphone-use / proportional construction',28,ink)+label(64,102,'B sheet · x = swipe width = 9 units · all dimensions set for this revision',17)
    ox,oy,k=180,140,5
    sheet+=f'<g transform="translate({ox} {oy}) scale({k})">'
    for x in [o['x'],o['x']+o['width']/2,o['x']+o['width'],g['arc_end'][0],g['arc_start'][0]]:sheet+=f'<path d="M{x} 0 V160" stroke="#D3D3CB" stroke-width=".17"/>'
    for y in [o['y'],o['y']+o['height'],sp['y'],s['center'][1],g['arc_end'][1]]:sheet+=f'<path d="M14 {y} H146" stroke="#D3D3CB" stroke-width=".17"/>'
    sheet+=mark('url(#hatch)')+f'<path d="{g["path"]}" fill="none" stroke="#55554F" stroke-width=".24"/>'
    for r in [s['radius']-s['width']/2,s['radius'],s['radius']+s['width']/2]:sheet+=f'<circle cx="{s["center"][0]}" cy="{s["center"][1]}" r="{r}" fill="none" stroke="#BDBDB2" stroke-width=".17"/>'
    for curve in g['phone_cubics']:
        sheet+=f'<path d="M{xy(curve[0])} '+ ' '.join('L'+xy(point) for point in curve[1:])+ '" fill="none" stroke="#A4A498" stroke-width=".18"/>'
        for point in curve:sheet+=f'<circle cx="{n(point[0])}" cy="{n(point[1])}" r=".45" fill="#7E7E73"/>'
    centers=[(c,s['width']/2) for c in g['cap_centers']]
    for c,r in centers:sheet+=f'<circle cx="{c[0]}" cy="{c[1]}" r="{r}" fill="none" stroke="#A4A498" stroke-width=".18"/>'
    for end in [g['arc_start'],g['arc_end']]:sheet+=f'<path d="M{xy(s["center"])} L{xy(end)}" stroke="#99998E" stroke-width=".18"/>'
    sheet+='</g>'
    def dim(a,b,t,tx,ty):return f'<path d="M{ox+k*a[0]} {oy+k*a[1]} L{ox+k*b[0]} {oy+k*b[1]}" stroke="#67675D"/>'+label(ox+k*tx,oy+k*ty,t,16,'#4B4B43','middle')
    sheet+=dim([o['x'],9],[o['x']+o['width'],9],f'{o["width"]}/{unit} x',o['x']+o['width']/2,6)
    sheet+=dim([24,o['y']],[24,o['y']+o['height']],f'{o["height"]}/{unit} x',13,81)
    sheet+=dim([s['center'][0]+s['radius']-s['width']/2,s['center'][1]],[s['center'][0]+s['radius']+s['width']/2,s['center'][1]],'x',s['center'][0]+s['radius'],s['center'][1]-4)
    sheet+=dim(s['center'],g['arc_start'],'R = 6x',s['center'][0]+s['radius']/2,s['center'][1]-4)
    extent=o['radius']*o['corner']['extent']
    sheet+=dim([o['x'],o['y']-4],[o['x']+extent,o['y']-4],f'{extent:.2f}',o['x']+extent/2,o['y']-7)
    for y,title,value in [(275,'DEVICE / CONTINUOUS',f'{o["width"]} × {o["height"]} / radius {o["radius"]}'),(385,'SWIPE ARC',f'R{s["radius"]} / {s["end_degrees"]-s["start_degrees"]}° / width {s["width"]}'),(495,'ARC CENTER',f'({s["center"][0]}, {s["center"][1]})'),(605,'TOP CAPSULE',f'{sp["width"]} × {sp["height"]} / R{sp["radius"]}')]:
        sheet+=label(1060,y,title,14)+label(1060,y+38,value,22,ink)
    sheet+=label(64,985,'Same compound path in the master, inverse and construction. Two true transparent cutouts.',17)
    sheet+=label(64,1024,'Phone: three cubic Beziers per corner, frozen SwiftUI continuous profile. Swipe: constant-width circular arc.',17)
    files['construction.svg']=document(sheet,1500,1080,'iphone-use swipe construction')
    for name,content in files.items():(out/name).write_text(content)
    (out/'resolved-geometry.json').write_text(json.dumps(g,indent=2)+'\n')
    (out/'manifest.json').write_text(json.dumps({'svg_sha256':{name:hashlib.sha256(content.encode()).hexdigest() for name,content in files.items()},'font':'Retained Geist Medium 500 vector outlines from previous A wordmark','input_sha256':hashlib.sha256((ROOT/'geometry.json').read_bytes()).hexdigest()},indent=2)+'\n')
    print(f'Built {len(files)} SVGs in {out}')

if __name__=='__main__':main()
