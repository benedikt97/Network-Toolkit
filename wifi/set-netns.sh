#!/bin/bash
iw phy phy0 set netns name $1
ip netns exec $1 iw dev
ip netns exec $1 /bin/bash
