"""STA-lite: graph-based NLDM static timing on a flat Yosys JSON netlist.

Model (pre-layout, ideal clocks):
  * all clock nets ideal: zero skew/latency, fixed slew CLK_SLEW
  * no wire RC; net load = sum of sink pin caps (+ optional per-fanout wire cap)
  * launch: flop CLK->Q at t=0; latch GATE->Q at its opening edge
  * capture: flop D setup to next capture edge; latch D setup to its closing edge
  * primary inputs arrive at IN_DELAY, primary outputs reported separately
  * latch transparency (time borrowing) and async reset/recovery not analysed
"""
import json, pickle, bisect, sys, collections, argparse

ap = argparse.ArgumentParser()
ap.add_argument('netlist'); ap.add_argument('libpkl')
ap.add_argument('--lib', default='sky130_hd_tt.lib')
ap.add_argument('--period', type=float, default=2.0)
ap.add_argument('--clk-slew', type=float, default=0.10)
ap.add_argument('--in-delay', type=float, default=0.0)
ap.add_argument('--wire-cap', type=float, default=0.0, help='pF added per sink (wire estimate)')
ap.add_argument('--max-cap', type=float, default=0.0, help='model buffer tree on nets above this load (pF), 0=off')
ap.add_argument('--exclude-start', default='', help='regex: ignore startpoints whose Q net matches')
ap.add_argument('--top', type=int, default=5)
ap.add_argument('--json-out')
args = ap.parse_args()

L = pickle.load(open(args.libpkl, 'rb'))
LIBFILE = args.lib
m = json.load(open(args.netlist))['modules']['rv32i_core']
T = args.period


def interp1(xs, x):
    if len(xs) == 1:
        return 0, 0, 0.0
    i = bisect.bisect_left(xs, x) - 1
    i = max(0, min(i, len(xs) - 2))
    return i, i + 1, (x - xs[i]) / (xs[i + 1] - xs[i])


def look(tab, x, y):
    i1, i2, v = tab
    if i1 is None:
        return v[0][0]
    if i2 is None or len(v[0]) == 1:
        a, b, f = interp1(i1, x)
        return v[a][0] + f * (v[b][0] - v[a][0]) if len(v) > 1 else v[0][0]
    a, b, f = interp1(i1, x)
    c, d, g = interp1(i2, y)
    v0 = v[a][c] + g * (v[a][d] - v[a][c])
    v1 = v[b][c] + g * (v[b][d] - v[b][c])
    return v0 + f * (v1 - v0)


# ---------------- build connectivity ----------------
cells = m['cells']
bitname = {}
for nn, nd in m['netnames'].items():
    if nd.get('hide_name'):
        continue
    for i, b in enumerate(nd['bits']):
        if isinstance(b, int) and (b not in bitname or len(nn) < len(bitname[b][0])):
            bitname[b] = (nn, i)
def bn(b):
    if b in bitname:
        n, i = bitname[b]
        w = len(m['netnames'][n]['bits'])
        return n + (f'[{i}]' if w > 1 else '')
    return f'net{b}'
def qname(cn):
    c = cells[cn]
    for p in ('Q', 'Q_N'):
        if p in c['connections'] and not isinstance(c['connections'][p][0], str):
            return bn(c['connections'][p][0])
    return cn
drivers = {}          # bit -> (cell, pin)
sinks = collections.defaultdict(list)   # bit -> [(cell,pin)]
port_in, port_out = {}, {}
for pname, p in m['ports'].items():
    for i, b in enumerate(p['bits']):
        if p['direction'] == 'input':
            port_in[b] = f'{pname}[{i}]'
        else:
            port_out.setdefault(b, []).append(f'{pname}[{i}]')
for cn, c in cells.items():
    lc = L[c['type']]
    for pin, bits in c['connections'].items():
        b = bits[0]
        if isinstance(b, str):
            continue
        if lc['pins'][pin]['dir'] == 'output':
            drivers[b] = (cn, pin)
        else:
            sinks[b].append((cn, pin))

CLKPINS = {'CLK', 'CLK_N', 'GATE', 'GATE_N'}
ASYNC = {'RESET_B', 'SET_B'}

# ---------------- clock network (ideal) ----------------
clk_root = [b for b, n in port_in.items() if n.startswith('clk_i')]
clock_nets = set()
seen_cells = set()
stack = list(clk_root)
while stack:
    b = stack.pop()
    if b in clock_nets:
        continue
    clock_nets.add(b)
    for cn, pin in sinks[b]:
        lc = L[cells[cn]['type']]
        if lc['seq'] or pin in CLKPINS:
            continue  # clock pin of a sequential element: stop
        # combinational cell in clock path (e.g. clock-gate AND): output is a clock net
        for op, bits in cells[cn]['connections'].items():
            if lc['pins'][op]['dir'] == 'output' and not isinstance(bits[0], str):
                stack.append(bits[0])
        seen_cells.add(cn)
clock_cells = seen_cells

# ---------------- net loads ----------------
def net_load(b):
    cap = 0.0
    for cn, pin in sinks.get(b, []):
        cap += L[cells[cn]['type']]['pins'][pin]['cap'] + args.wire_cap
    return cap


load = {}
# ---------------- timing graph ----------------
# node = net bit; arrival per transition r/f; store (time, slew, pred)
INF = float('-inf')
arr = {}   # bit -> {'r':(t,slew,pred), 'f':...}


def setarr(b, tr, t, s, pred):
    cur = arr.setdefault(b, {})
    if tr not in cur or t > cur[tr][0]:
        cur[tr] = (t, s, pred)


def ldof(b):
    if b not in load:
        load[b] = net_load(b)
    return min(load[b], args.max_cap) if args.max_cap > 0 else load[b]


import math, re as _re
BUF = None
if args.max_cap > 0:
    from libparse import extract as _ex
    BUF = _ex(LIBFILE, {'sky130_fd_sc_hd__buf_4'})['sky130_fd_sc_hd__buf_4']['pins']['X']['arcs'][0]


def buftree(b, t, s):
    # ideal buffer tree (buf_4, fanout-of-maxcap per level) for heavily loaded nets
    if not BUF or load[b] <= args.max_cap:
        return t, s
    lv = math.ceil(math.log(load[b] / args.max_cap, 4))
    for _ in range(lv):
        d = (look(BUF['cell_rise'], s, args.max_cap) + look(BUF['cell_fall'], s, args.max_cap)) / 2
        s = (look(BUF['rise_transition'], s, args.max_cap) + look(BUF['fall_transition'], s, args.max_cap)) / 2
        t += d
    return t, s


launch_cnt = 0
# startpoints: sequential outputs
for cn, c in cells.items():
    lc = L[c['type']]
    if not lc['seq'] or cn in clock_cells:
        continue
    for op, pdef in lc['pins'].items():
        if pdef['dir'] != 'output' or op not in c['connections']:
            continue
        qb = c['connections'][op][0]
        if isinstance(qb, str) or qb in clock_nets:
            continue
        if args.exclude_start and _re.search(args.exclude_start, bn(qb)):
            continue
        for a in pdef['arcs']:
            if a['type'] not in ('rising_edge', 'falling_edge'):
                continue
            t0 = 0.0 if a['type'] == 'rising_edge' else T / 2   # active-low latch opens at falling edge
            ld = ldof(qb)
            for tr, dk, sk in (('r', 'cell_rise', 'rise_transition'), ('f', 'cell_fall', 'fall_transition')):
                if dk in a:
                    tt_, ss_ = buftree(qb, t0 + look(a[dk], args.clk_slew, ld), look(a[sk], args.clk_slew, ld))
                    setarr(qb, tr, tt_, ss_, ('launch', cn, a['from'] + '->' + op, t0))
            launch_cnt += 1
for b, n in port_in.items():
    if b in clock_nets or n.startswith('rst_ni'):
        continue
    for tr in 'rf':
        setarr(b, tr, args.in_delay, args.clk_slew, ('input', n))

# combinational arcs: topological propagation over non-sequential, non-clock cells
comb = [cn for cn, c in cells.items() if not L[c['type']]['seq'] and cn not in clock_cells]
indeg = {}
cell_out = {}
cell_inbits = {}
for cn in comb:
    c = cells[cn]; lc = L[c['type']]
    ins = [c['connections'][p][0] for p, d in lc['pins'].items() if d['dir'] == 'input' and p in c['connections']]
    ins = [b for b in ins if not isinstance(b, str)]
    cell_inbits[cn] = ins
    cell_out[cn] = [(p, c['connections'][p][0]) for p, d in lc['pins'].items() if d['dir'] == 'output' and p in c['connections']]
    indeg[cn] = 0
# Kahn over cells
comb_set = set(comb)
deps = collections.defaultdict(list)
for cn in comb:
    for b in cell_inbits[cn]:
        if b in drivers and drivers[b][0] in comb_set:
            indeg[cn] += 1
            deps[drivers[b][0]].append(cn)
q = collections.deque(cn for cn in comb if indeg[cn] == 0)
order = []
while q:
    cn = q.popleft(); order.append(cn)
    for nx in deps[cn]:
        indeg[nx] -= 1
        if indeg[nx] == 0:
            q.append(nx)
loops = len(comb) - len(order)

for cn in order:
    c = cells[cn]; lc = L[c['type']]
    for op, ob in cell_out[cn]:
        if isinstance(ob, str):
            continue
        ld = ldof(ob)
        for a in lc['pins'][op]['arcs']:
            if a['type'] != 'combinational' or a['from'] not in c['connections']:
                continue
            ib = c['connections'][a['from']][0]
            if isinstance(ib, str) or ib not in arr:
                continue
            sense = a['sense']
            for otr, dk, sk in (('r', 'cell_rise', 'rise_transition'), ('f', 'cell_fall', 'fall_transition')):
                if dk not in a:
                    continue
                if sense == 'positive_unate':
                    itrs = [otr]
                elif sense == 'negative_unate':
                    itrs = ['f' if otr == 'r' else 'r']
                else:
                    itrs = ['r', 'f']
                for itr in itrs:
                    if itr not in arr[ib]:
                        continue
                    t, s, _ = arr[ib][itr]
                    tt_, ss_ = buftree(ob, t + look(a[dk], s, ld), look(a[sk], s, ld))
                    setarr(ob, otr, tt_, ss_, ('arc', cn, f"{a['from']}->{op}", ib, itr))

# ---------------- endpoints ----------------
ends = []
for cn, c in cells.items():
    lc = L[c['type']]
    if not lc['seq']:
        continue
    for pin, pdef in lc['pins'].items():
        if pdef['dir'] != 'input' or pin in CLKPINS or pin in ASYNC or pin not in c['connections']:
            continue
        b = c['connections'][pin][0]
        if isinstance(b, str) or b not in arr:
            continue
        for a in pdef['arcs']:
            if not a['type'].startswith('setup'):
                continue
            # capture edge
            if lc['seq'] == 'ff':
                cap = T if a['type'] == 'setup_rising' else T / 2
            else:   # latch closing edge
                cap = T / 2 if a['type'] == 'setup_falling' else T
            for tr, ck in (('r', 'rise_constraint'), ('f', 'fall_constraint')):
                if tr in arr[b] and ck in a:
                    t, s, _ = arr[b][tr]
                    req = cap - look(a[ck], args.clk_slew, s)
                    kind = 'clock-gate enable' if cn in clock_cells else lc['seq']
                    ends.append((req - t, t, req, cn, pin, b, tr, kind))
io_ends = []
for b, names in port_out.items():
    if b in arr:
        tr, (t, s, _) = max(arr[b].items(), key=lambda kv: kv[1][0])
        io_ends.append((t, names[0], b, tr))


def trace(b, tr):
    path = []
    while True:
        t, s, pred = arr[b][tr]
        if pred[0] == 'arc':
            _, cn, arc, ib, itr = pred
            path.append((t, s, cells[cn]['type'].replace('sky130_fd_sc_hd__', ''), bn(b), arc, tr))
            b, tr = ib, itr
        else:
            if pred[0] == 'launch':
                path.append((t, s, cells[pred[1]]['type'].replace('sky130_fd_sc_hd__', ''), qname(pred[1]), pred[2], tr))
            else:
                path.append((t, s, 'INPUT', pred[1], '', tr))
            return path[::-1]


ends.sort()
print(f'period {T:.3f} ns ({1000/T:.0f} MHz)  clk_slew {args.clk_slew} ns  in_delay {args.in_delay} ns  wire_cap/sink {args.wire_cap} pF')
print(f'cells {len(cells)}  clock-network cells {len(clock_cells)}  launch arcs {launch_cnt}  comb loops (cells not ordered) {loops}')
wns = ends[0][0]
tns = sum(min(0, e[0]) for e in {(e[3], e[4]): e for e in ends}.values())
viol = len({(e[3], e[4]) for e in ends if e[0] < 0})
print(f'WNS {wns:.3f} ns   TNS {tns:.3f} ns   failing endpoints {viol} / {len({(e[3], e[4]) for e in ends})}')
fmax = 1000.0 / (T - wns)
print(f'max frequency (reg-to-reg, this model) ~ {fmax:.0f} MHz  (min period {T - wns:.3f} ns)')
shown = set()
k = 0
for e in ends:
    key = (e[3], e[4])
    if key in shown:
        continue
    shown.add(key); k += 1
    if k > args.top:
        break
    slack, t, req, cn, pin, b, tr, kind = e
    p = trace(b, tr)
    print(f'\n--- path {k}: slack {slack:.3f} ns  arrival {t:.3f}  required {req:.3f}  endpoint {qname(cn)} .{pin} ({kind})')
    print(f'    start {p[0][3]} ({p[0][2]} {p[0][4]})   logic depth {len(p) - 1} cells')
    for t_, s_, typ, cn_, arc, tr_ in p:
        print(f'    {t_:7.3f}  {tr_}  slew {s_:.3f}  {typ:<14} {arc:<12} {cn_[-70:]}')
io_ends.sort(reverse=True)
print('\nworst primary-output arrivals (input delay 0, no output constraint):')
for t, n, b, tr in io_ends[:5]:
    print(f'    {t:.3f} ns  {n}')
if args.json_out:
    json.dump({'period': T, 'wns': wns, 'tns': tns, 'viol': viol, 'fmax': fmax,
               'endpoints': len({(e[3], e[4]) for e in ends}),
               'top_paths': [{'slack': e[0], 'end': qname(e[3]) + '.' + e[4], 'kind': e[7],
                              'path': trace(e[5], e[6])} for e in ends[:1]],
               'slack_hist': sorted(e[0] for e in {(e[3], e[4]): e for e in ends}.values())},
              open(args.json_out, 'w'))
