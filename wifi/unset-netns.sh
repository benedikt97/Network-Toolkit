#!/bin/bash
ip netns exec $1 iw phy phy0 set netns 1
