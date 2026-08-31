# ADR-002: Move worker nodes to private subnets behind a single NAT gateway

**Status:** Accepted
**Date:** 2026-08-31
**Supersedes:** [ADR-001](001-public-subnets.md) (public-subnet-only topology)

## Context

The initial EKS topology placed worker nodes in public subnets with
`map_public_ip_on_launch = true` and no NAT gateway, chosen to avoid the
~$32/month NAT cost during early development.

That topology gives every worker node a public IP, directly addressable from the
internet. The only control preventing access is the node security group. A
misconfigured rule — or a vulnerability in anything listening on the node — is
directly exposed. There is no network-layer defence in depth.

Verified before the change:

```
NAME                                        EXTERNAL-IP
ip-10-0-2-17.ap-south-1.compute.internal    15.252.173.229
ip-10-0-2-65.ap-south-1.compute.internal    15.252.137.22
```

## Options considered

**1. Keep public subnets.**
Free. Nodes remain internet-addressable, protected only by security groups.

**2. Private subnets, one NAT gateway per AZ.**
~$64/month plus $0.045/GB processed. Egress survives the loss of an availability
zone. Standard for production workloads with strict uptime requirements.

**3. Private subnets, one shared NAT gateway.**
~$32/month plus $0.045/GB. Nodes are not internet-addressable. Egress depends on
a single AZ; if that AZ fails, no node can pull images or make outbound API calls.

## Decision

**Option 3.**

Network-layer isolation of worker nodes is worth $32/month even for a
demonstration platform. It is the topology I would defend in a production
security review, and building it any other way would misrepresent the project.

Per-AZ NAT is not worth the additional $32/month **at this scale and for this
workload**. The failure it protects against — losing the AZ hosting the NAT
gateway — degrades *egress only*. Pods already running continue serving inbound
traffic through the ALB, which spans both AZs and does not route through NAT. The
blast radius is "cannot deploy or scale until NAT is restored", not "the service
is down".

**That reasoning depends on the workload.** This service answers requests from
memory with no outbound dependencies. A service that called an external API to
serve each request — a payment gateway, say — would go fully down on egress loss,
and option 2 would become mandatory. The decision is workload-specific, not a
general rule.

## Consequences

### Positive

- Worker nodes have no public IP and cannot be reached directly from the internet
- Inbound traffic is constrained to a single controlled path: ALB → node
- Two independent layers now protect the nodes (no public IP **and** no inbound
  route), rather than security group rules alone
- Matches the topology expected in a production security review

### Negative

- **+$32/month** base cost, plus $0.045/GB of NAT data processing
- **Single point of failure for egress** in the NAT gateway's AZ
- **Applying this change replaces the node group.** `terraform plan` reported
  `# forces replacement` on `subnet_ids` — AWS cannot move an EC2 instance
  between subnets, so the group is destroyed and recreated. This caused brief
  downtime while pods rescheduled. In production this would be done with a second
  node group and a controlled drain rather than an in-place replacement.
- Debugging is harder: nodes are no longer directly SSH-able and would require
  SSM Session Manager or a bastion host

### Discovered during verification: both nodes landed in the same AZ

After the change, both nodes came up in `ap-south-1b`:

```
ip-10-0-12-189.ap-south-1.compute.internal   10.0.12.189
ip-10-0-12-72.ap-south-1.compute.internal    10.0.12.72
```

`desired_size = 2` across two private subnets does not guarantee one node per AZ —
the managed node group's autoscaling group chose to place both in the same zone.

**This is a larger availability risk than the NAT dependency this ADR set out to
reason about.** Losing `ap-south-1b` would take out the entire cluster, not just
egress. It is not addressed here; the fix is either a topology spread constraint
on workloads, or separate per-AZ node groups with `desired_size = 1` each.

Logged as follow-up work rather than silently corrected, because it was found by
checking the result rather than predicted by the design.

## Verification

Three checks, each mapping to a claim in this document.

**1. Nodes have no public IP**

```
$ kubectl get nodes -o wide
NAME                                          STATUS  INTERNAL-IP   EXTERNAL-IP
ip-10-0-12-189.ap-south-1.compute.internal    Ready   10.0.12.189   <none>
ip-10-0-12-72.ap-south-1.compute.internal     Ready   10.0.12.72    <none>
```

Evidence: `docs/nodes-private-phase6.png`, compared against
`docs/nodes-public-ips-phase5.png`.

**2. Egress works through NAT**

The entire platform bootstrapped from scratch on private nodes — ArgoCD (7 pods),
Prometheus stack, Kyverno, and the demo app all pulled images from GHCR, quay.io
and public Helm repositories with no public IP on any node. A subsequent
`kubectl rollout restart deployment/demo` cycled pods successfully.

Had the private route table been misconfigured, every pod would have stalled in
`ImagePullBackOff`.

Evidence: `docs/nat-egress-works-phase6.png`.

**3. Inbound still works through the ALB**

```
$ kubectl get ingress
NAME   CLASS   ADDRESS                                                              PORTS
demo   alb     k8s-default-demo-549c5efb33-1805131101.ap-south-1.elb.amazonaws.com  80

$ curl http://k8s-default-demo-549c5efb33-1805131101.ap-south-1.elb.amazonaws.com
hello from the platform
```

The ALB is placed in the public subnets via the `kubernetes.io/role/elb` tag and
forwards to pods over private addresses inside the VPC. Those subnet tags are
load-bearing configuration: without them the controller cannot discover where to
place the load balancer, and the Ingress sits without an address and without a
clear error.

Evidence: `docs/phase6-all-three-checks.png`.
