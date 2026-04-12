# Runbook: EKS Node NotReady

**Severity:** P2 (degraded capacity) → P1 if ≥ 50 % of nodes affected  
**On-call rotation:** SRE  
**Last reviewed:** 2025-04-01

---

## Symptoms

- `kubectl get nodes` shows one or more nodes in `NotReady` state.
- Pods on the affected node transition to `Unknown` or are evicted.
- Cluster Autoscaler may start provisioning replacement nodes.
- Grafana "Node Health" dashboard shows a red tile for the affected node.

---

## Triage Steps

### 1. Identify the affected node(s)

```bash
kubectl get nodes -o wide | grep -v Ready
```

### 2. Describe the node for events

```bash
kubectl describe node <NODE_NAME>
```

Look for:
- `KubeletNotReady` — kubelet lost contact with the API server.
- `NetworkPluginNotReady` — Cilium DaemonSet not running on this node.
- `DiskPressure` / `MemoryPressure` — resource exhaustion.
- `NodeHasSufficientMemory` transitions in the event log.

### 3. Check Cilium on the node

```bash
kubectl -n kube-system get pods -o wide | grep cilium | grep <NODE_NAME>
kubectl -n kube-system logs <CILIUM_POD> --previous
```

### 4. Check kubelet and system logs via SSM

```bash
# Open an SSM session to the EC2 instance backing the node
aws ssm start-session --target <INSTANCE_ID>

# Once connected:
sudo journalctl -u kubelet -n 100 --no-pager
sudo journalctl -u containerd -n 50 --no-pager
df -h          # check disk pressure
free -m        # check memory pressure
```

### 5. Check EC2 instance health in AWS Console

- **EC2 → Instances → <INSTANCE_ID> → Status checks** — look for system/instance failures.
- **EC2 → Auto Scaling Groups → <ASG_NAME>** — verify the ASG is healthy and not in a lifecycle hook.

---

## Remediation

### Scenario A: Transient kubelet crash

Restart the kubelet via SSM:

```bash
sudo systemctl restart kubelet
# Wait 30 s, then verify:
kubectl get node <NODE_NAME>
```

### Scenario B: Disk pressure

```bash
# Find large ephemeral logs
sudo du -sh /var/log/containers/* | sort -rh | head -20
sudo journalctl --vacuum-size=1G
# If root volume is full, consider cordoning and draining for volume expansion
```

### Scenario C: Cilium not running

```bash
kubectl -n kube-system rollout restart daemonset/cilium
kubectl -n kube-system rollout status daemonset/cilium
```

### Scenario D: EC2 hardware failure (status check failed)

Cordon and drain the node, then terminate it — the ASG will replace it:

```bash
kubectl cordon <NODE_NAME>
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data --grace-period=60
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

Monitor the replacement node coming up:

```bash
watch kubectl get nodes
```

---

## Escalation

| Condition | Action |
|---|---|
| > 2 nodes NotReady simultaneously | Page the SRE lead; consider an AZ-level issue |
| All nodes in a node group NotReady | Escalate to AWS Support (P1 ticket) |
| Nodes recover but pods remain Unknown | Force-delete stuck pods: `kubectl delete pod <POD> --grace-period=0 --force` |

---

## Prevention / Follow-up

- Ensure Cluster Autoscaler is running and node group min/max are correctly sized.
- Review Prometheus alert `KubeNodeNotReady` threshold — default fires after 15 min; tune to 5 min for production.
- Confirm node group launch template has sufficient root-volume size (≥ 50 GiB for prod).
- Add this incident to the weekly SRE review and update SLO burn-rate dashboards if applicable.
