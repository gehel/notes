#!/usr/bin/python3
"""Render an nwdiag source file, working around an upstream Python 3 bug.

nwdiag 2.0.0 aborts with

    TypeError: '<' not supported between instances of 'Network' and 'Network'

whenever the first node of a group belongs to more than one network -- which is
exactly what a router does, since it sits on every subnet it serves.

The cause is nwdiag/metrics.py:162, in GroupMetrics.__init__:

    networks = group.nodes[0].networks[:]
    networks.sort(key=lambda a: a.xy.y)
    network = min(networks)

The list is already sorted by vertical position, so the intent is plainly "take
the topmost network" -- networks[0]. The min() call is redundant, and Network
defines no ordering, so on Python 3 it raises. It goes unnoticed because min()
on a single-element list never invokes __lt__, so the bug only appears once a
node spans two networks.

Defining __lt__ on the same key the sort uses makes min() agree with the sort
rather than papering over it. Nothing else in the diagram changes.

Usage is identical to nwdiag3:

    ./render-nwdiag.py -T svg network-addressing.nwdiag -o network-addressing.svg
"""

import sys

from nwdiag.command import main
from nwdiag.elements import Network

Network.__lt__ = lambda self, other: self.xy.y < other.xy.y

if __name__ == "__main__":
    sys.exit(main())
