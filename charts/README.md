# Charts

These Helm chart directories were extracted from their OCI registries and committed as-is.
No modifications were made to chart templates or default values.

## Source

| Chart | OCI Source | Version | Pulled |
|-------|-----------|---------|--------|
| `openshell-gateway/` | `oci://ghcr.io/nvidia/openshell/helm-chart` | 0.1.3 | `helm pull --untar` |
| `openshell-dashboard/` | `oci://ghcr.io/gkrumbach07/openshell-dashboard/helm-chart/openshell-dashboard` | 0.1.1 | `helm pull --untar` |

## How to re-pull (requires internet)

```bash
helm pull oci://ghcr.io/nvidia/openshell/helm-chart --version 0.1.3 --untar --untardir charts/
mv charts/helm-chart charts/openshell-gateway

helm pull oci://ghcr.io/gkrumbach07/openshell-dashboard/helm-chart/openshell-dashboard --version 0.1.1 --untar --untardir charts/
```
