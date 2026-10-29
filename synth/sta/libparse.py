"""Minimal Liberty parser: extracts pins, caps, NLDM timing arcs for a set of cells."""
import re, pickle, sys

TOK = re.compile(r'\s*(?:(/\*.*?\*/)|(\\\n)|("(?:[^"\\]|\\.)*")|([{}();:,])|([^\s{}();:,"]+))', re.S)


def tokens(text):
    pos = 0
    n = len(text)
    while pos < n:
        m = TOK.match(text, pos)
        if not m:
            break
        pos = m.end()
        if m.group(1) or m.group(2):
            continue
        if m.group(3) is not None:
            yield ('S', m.group(3)[1:-1])
        elif m.group(4):
            yield ('P', m.group(4))
        elif m.group(5):
            yield ('W', m.group(5))


class Group:
    __slots__ = ('kind', 'args', 'attrs', 'groups')

    def __init__(self, kind, args):
        self.kind, self.args, self.attrs, self.groups = kind, args, {}, []

    def sub(self, kind):
        return [g for g in self.groups if g.kind == kind]


def parse_group_body(tk, grp):
    # after '{'
    while True:
        t = next(tk)
        if t == ('P', '}'):
            return grp
        name = t[1]
        t2 = next(tk)
        if t2 == ('P', ':'):
            val = next(tk)[1]
            t3 = next(tk)
            # tolerate missing ';'
            if t3 != ('P', ';'):
                # push back not supported; assume next token begins new statement
                tk_push.append(t3)
            grp.attrs[name] = val
        elif t2 == ('P', '('):
            args = []
            while True:
                a = next(tk)
                if a == ('P', ')'):
                    break
                if a == ('P', ','):
                    continue
                args.append(a[1])
            t3 = next(tk)
            if t3 == ('P', '{'):
                g = Group(name, args)
                parse_group_body(tk, g)
                grp.groups.append(g)
            else:
                grp.attrs.setdefault(name, args)  # complex attribute
        else:
            raise SyntaxError(f'unexpected {t} {t2}')


tk_push = []


def gen(text):
    for t in tokens(text):
        while tk_push:
            yield tk_push.pop()
        yield t


def floats(s):
    return [float(x) for x in s.replace('"', '').replace('\\', '').split(',') if x.strip()]


def table(g):
    i1 = floats(g.attrs['index_1'][0]) if 'index_1' in g.attrs else None
    i2 = floats(g.attrs['index_2'][0]) if 'index_2' in g.attrs else None
    vals = [floats(v) for v in g.attrs['values']]
    return (i1, i2, vals)


def extract(libfile, wanted):
    text = open(libfile).read()
    out = {}
    # split by cell to avoid parsing whole library
    for m in re.finditer(r'\n\s*cell\s*\(\s*"?([\w]+)"?\s*\)\s*\{', text):
        name = m.group(1)
        if name not in wanted:
            continue
        # find matching brace
        depth, i = 1, m.end()
        while depth:
            c = text[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
        body = text[m.end():i]
        tk_push.clear()
        g = Group('cell', [name])
        parse_group_body(gen(body), g)
        cell = {'area': float(g.attrs.get('area', 0)), 'pins': {}, 'seq': None}
        if g.sub('ff'):
            cell['seq'] = 'ff'
        if g.sub('latch'):
            cell['seq'] = 'latch'
        for p in g.sub('pin'):
            pin = {'dir': p.attrs.get('direction'), 'cap': float(p.attrs.get('capacitance', 0) or 0),
                   'clock': p.attrs.get('clock') == 'true', 'arcs': []}
            for t in p.sub('timing'):
                arc = {'from': t.attrs.get('related_pin'), 'type': t.attrs.get('timing_type', 'combinational'),
                       'sense': t.attrs.get('timing_sense', 'non_unate')}
                for k in ('cell_rise', 'cell_fall', 'rise_transition', 'fall_transition',
                          'rise_constraint', 'fall_constraint'):
                    s = t.sub(k)
                    if s:
                        arc[k] = table(s[0])
                pin['arcs'].append(arc)
            cell['pins'][p.args[0]] = pin
        out[name] = cell
    return out


if __name__ == '__main__':
    lib, wanted_file, outp = sys.argv[1:4]
    wanted = set(open(wanted_file).read().split())
    res = extract(lib, wanted)
    print('parsed', len(res), 'of', len(wanted))
    pickle.dump(res, open(outp, 'wb'))
