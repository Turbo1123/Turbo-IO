"""Deterministic SVG developer preview. Not a pixel-accurate firmware screenshot."""
from html import escape
from .contracts import validate
from .app_package import validate_app


def render(document, page=None):
    app = page is not None
    if app:
        validate_app(document)
        selected = next((p for p in document['pages'] if p['id'] == page), None)
        if selected is None: raise ValueError('Unknown page')
        width, height, items = 540, 180, selected['components']
    else:
        validate(document); width, height, items = 256, 194, document['components']
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           '<title>Turbo IO developer layout preview; not a device screenshot</title>',
           f'<rect width="{width}" height="{height}" fill="black"/>']
    for i, c in enumerate(items):
        x,y,w,h = (c[k] for k in ('x','y','w','h')); kind=c['kind']
        out.append(f'<clipPath id="clip{i}"><rect x="{x}" y="{y}" width="{w}" height="{h}"/></clipPath>')
        out.append(f'<g clip-path="url(#clip{i})">')
        if kind in ('text','button'):
            if kind=='button': out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="#123712" stroke="#4fff54"/>')
            align = c.get('align', 'left'); tx = x + (w/2 if align=='center' else w if align=='right' else 0)
            anchor = {'left':'start','center':'middle','right':'end'}[align]
            out.append(f'<text x="{tx}" y="{y+c["font"]}" fill="#4fff54" font-size="{c["font"]}" font-family="sans-serif" text-anchor="{anchor}">{escape(c["text"])}</text>')
        elif kind=='progress':
            out.extend([f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#143714"/>',f'<rect x="{x}" y="{y}" width="{w*c["value"]/100}" height="{h}" fill="#4fff54"/>'])
        elif kind in ('image','icon'):
            if kind=='icon':
                # System icon glyphs are platform supplied; never mislabel box as the actual glyph.
                out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="#4fff54"/><text x="{x+2}" y="{y+12}" fill="#4fff54" font-size="10">i{c["icon"]}</text>')
            else:
                import base64
                raw=base64.b64decode(document['assets'][c['asset']]['pixels'] if app else c['pixels'])
                for row in range(h):
                    for col in range(w):
                        bit=row*w+col
                        if raw[bit//8] & (128>>(bit%8)): out.append(f'<rect x="{x+col}" y="{y+row}" width="1" height="1" fill="#4fff54"/>')
        elif kind=='frame': out.append(f'<rect x="{x+1}" y="{y+1}" width="{w-2}" height="{h-2}" fill="none" stroke="#4fff54"/>')
        elif kind=='divider': out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#4fff54"/>')
        elif kind=='barChart':
            step=w/len(c['points'])
            for j,v in enumerate(c['points']): out.append(f'<rect x="{x+j*step}" y="{y+h-h*v/100}" width="{max(1,step-3)}" height="{h*v/100}" fill="#4fff54"/>')
        elif kind=='lineChart':
            points=' '.join(f'{x+j*w/(len(c["points"])-1)},{y+h-h*v/100}' for j,v in enumerate(c['points']))
            out.append(f'<polyline points="{points}" fill="none" stroke="#4fff54" stroke-width="2"/>')
        out.append('</g>')
    return ''.join(out)+'</svg>'
