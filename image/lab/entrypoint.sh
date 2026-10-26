#!/bin/bash
# Boot sequence for every node: wait for containerlab to plug the cables in,
# apply common host config, then the node's role.
set -u
HOST=$(hostname)
exec > >(tee -a /var/log/lab-boot.log) 2>&1

# containerlab sets CLAB_INTFS = number of data interfaces it will attach (eth1..ethN)
want=${CLAB_INTFS:-0}
for _ in $(seq 1 120); do
  have=$(ls /sys/class/net | grep -c '^eth[1-9]')
  [ "$have" -ge "$want" ] && break
  sleep 0.5
done
echo "[boot] $HOST role=${ROLE:-none} interfaces=$have/$want"

source /lab/roles/common.sh
[ -n "${ROLE:-}" ] && source "/lab/roles/${ROLE}.sh"
echo "[boot] $HOST done"

touch /run/lab-ready
exec sleep infinity
