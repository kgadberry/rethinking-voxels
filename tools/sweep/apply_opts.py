import re,sys
# Emulate Iris option substitution over an already-flattened source.
src=open(sys.argv[1]).read().split("\n")
cfg={}
for line in open(sys.argv[2]):
    line=line.strip()
    if not line or line.startswith("#"): continue
    k,_,v=line.partition("="); cfg[k.strip()]=v.strip()

boolset=set(); valset=set(); constset=set()
out=[]
for line in src:
    m=re.match(r'^(\s*)(//)?\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)\s*$', line)
    if m and m.group(3) in cfg:                      # boolean option
        ind,name=m.group(1),m.group(3); boolset.add(name)
        on = cfg[name].lower()=="true"
        out.append(f"{ind}#define {name}" if on else f"{ind}//#define {name}")
        continue
    m=re.match(r'^(\s*)#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(\S+)(\s*//.*)?$', line)
    if m and m.group(2) in cfg:                      # value option
        ind,name=m.group(1),m.group(2); valset.add(name)
        out.append(f"{ind}#define {name} {cfg[name]}{m.group(4) or ''}")
        continue
    m=re.match(r'^(\s*)const\s+(\w+)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\S+?);(\s*//.*)?$', line)
    if m and m.group(3) in cfg:                      # const option
        ind,ty,name=m.group(1),m.group(2),m.group(3); constset.add(name)
        out.append(f"{ind}const {ty} {name} = {cfg[name]};{m.group(5) or ''}")
        continue
    out.append(line)
open(sys.argv[3],"w").write("\n".join(out))
applied=boolset|valset|constset
unmatched=sorted(set(cfg)-applied)
print(f"applied {len(applied)} of {len(cfg)}: bool={len(boolset)} value={len(valset)} const={len(constset)}")
if unmatched: print("not present in this program's include tree:", ", ".join(unmatched))
