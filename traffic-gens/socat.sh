while :
do
  socat -d UDP-RECVFROM:5001,broadcast,fork UDP-SENDTO:192.168.30.51:5002
done
