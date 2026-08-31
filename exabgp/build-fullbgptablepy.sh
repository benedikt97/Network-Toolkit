#!/bin/bash
wget http://data.ris.ripe.net/rrc00/latest-bview.gz
mrt2exabgp -G -P latest-bview.gz > fullbgptable.py
rm latest-bview.gz
sed -i -E "s/(next-hop ).+( nlri)/\1self\2/g" fullbgptable.py

