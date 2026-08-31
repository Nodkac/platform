# ADR-001: Public-subnet-only VPC topology, no NAT gateway

**Status:** Superseded by [ADR-002](002-private-subnets.md)
**Date:** 2026-08-20

## Context

The platform needed a VPC and an EKS cluster to demonstrate that the same GitOps
manifests deploy unchanged to a cloud environment. The cluster would be created
and destroyed repeatedly across short sessions rather than run continuously.

A NAT gateway — the standard way to give private machines outbound internet
access — costs **~$32/month whether or not it is used**, billed hourly from the
moment it exists. Against a target total project spend of $10–20, that is the
single largest line item, larger than the EKS control plane over a month.

## Options considered

**1. Public subnets, nodes with public IPs, no NAT.**
Free. Nodes reach the internet directly for image pulls.

**2. Private subnets with a NAT gateway.**
~$32/month plus data processing. Nodes are unreachable from the internet.

## Decision

**Option 1**, explicitly as a temporary cost measure for the initial build.

Nodes are placed in public subnets with `map_public_ip_on_launch = true`, giving
each a public IP so it can pull container images without NAT.

This is **not** the topology I would run in production. It is chosen knowingly to
keep the first cloud milestone cheap, with the migration to private subnets
planned as the next piece of work.

## Consequences

- **Every worker node is directly addressable from the internet.** The only
  control preventing access is the node security group. There is no
  network-layer defence in depth.
- Saves ~$32/month plus per-GB data processing charges
- Simpler topology: no NAT gateway, no Elastic IP, no private route table, and
  correspondingly fewer resources to clean up at teardown
- Migrating later requires **replacing the node group**, because AWS cannot move
  an EC2 instance between subnets

## Follow-up

Superseded by ADR-002, which moves the nodes into private subnets behind a single
NAT gateway.
