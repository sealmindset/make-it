import sys, html
from html.parser import HTMLParser
class P(HTMLParser):
    def __init__(s):
        super().__init__(); s.out=[]; s.skip=0
    def handle_starttag(s,t,a):
        if t in('script','style','noscript'): s.skip+=1
        if t in('p','div','br','li','tr','h1','h2','h3','h4','h5','table','section','article','pre'): s.out.append('\n')
        if t in('h1','h2','h3','h4'): s.out.append('#'*int(t[1])+' ')
        if t=='li': s.out.append('- ')
        if t in('td','th'): s.out.append(' | ')
        if t=='a':
            d=dict(a); 
            if d.get('href'): s.out.append('[')
            s._href=d.get('href')
    def handle_endtag(s,t):
        if t in('script','style','noscript'): s.skip-=1
        if t=='a' and getattr(s,'_href',None): s.out.append(f']({s._href})'); s._href=None
    def handle_data(s,d):
        if not s.skip: s.out.append(d)
p=P(); p.feed(open(sys.argv[1],encoding='utf-8',errors='replace').read())
import re
t=''.join(p.out); t=re.sub(r'[ \t]+',' ',t); t=re.sub(r'\n\s*\n+','\n\n',t)
print(t)
