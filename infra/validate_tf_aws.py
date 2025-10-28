#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional

# ---------------------------
# Parámetros editables (o usar argv/env)
# ---------------------------
REGION = os.getenv("AWS_REGION", "us-east-1")
CLUSTER_NAME = os.getenv("EKS_CLUSTER_NAME", "fastticket-eks")
PROJECT_TAG = os.getenv("PROJECT_TAG", "fastticket")  # se usará en filtros de VPC/Subnets
ACCOUNT_ID = os.getenv("AWS_ACCOUNT_ID", "665516437576")

# Directorio base para outputs
BASE_OUTDIR = Path("validation_output")

# ---------------------------
# Utilidades
# ---------------------------
def which(cmd: str) -> Optional[str]:
    from shutil import which as _which
    return _which(cmd)

def run(cmd: str, timeout: int = 120) -> Dict[str, Any]:
    """Ejecuta comando en shell seguro, captura salida y código de retorno."""
    try:
        proc = subprocess.run(
            shlex.split(cmd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
            text=True
        )
        return {
            "cmd": cmd,
            "rc": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
        }
    except Exception as e:
        return {"cmd": cmd, "rc": 997, "stdout": "", "stderr": f"exception: {e}"}

def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        f.write(text)

def parse_json_or_raw(s: str) -> Any:
    try:
        return json.loads(s)
    except Exception:
        return {"raw": s}

def status(pass_bool: bool) -> str:
    return "PASS" if pass_bool else "FAIL"

# ---------------------------
# Validaciones
# ---------------------------
def check_sts(outdir: Path) -> Dict[str, Any]:
    res = run("aws sts get-caller-identity")
    write_json(outdir / "aws_sts_get_caller_identity.json", parse_json_or_raw(res["stdout"]))
    ok = res["rc"] == 0 and ACCOUNT_ID in res["stdout"]
    return {"name": "STSIdentity", "status": status(ok), "detail": res}

def check_vpc(outdir: Path) -> Dict[str, Any]:
    # VPC por tag Name=<project>-vpc (coincidir con Terraform)
    res_vpc = run(f'aws ec2 describe-vpcs --filters Name=tag:Name,Values={PROJECT_TAG}-vpc --region {REGION}')
    vpcs = parse_json_or_raw(res_vpc["stdout"])
    write_json(outdir / "ec2_describe_vpcs.json", vpcs)
    ok_vpc = res_vpc["rc"] == 0 and vpcs.get("Vpcs")

    # IGW asociado
    res_igw = run(f'aws ec2 describe-internet-gateways --filters Name=attachment.state,Values=available --region {REGION}')
    igw = parse_json_or_raw(res_igw["stdout"])
    write_json(outdir / "ec2_describe_internet_gateways.json", igw)
    ok_igw = res_igw["rc"] == 0 and igw.get("InternetGateways")

    # Subnets públicas (esperamos al menos 2 en AZs)
    res_sn = run(f'aws ec2 describe-subnets --filters Name=tag:Name,Values={PROJECT_TAG}-public-* --region {REGION}')
    subnets = parse_json_or_raw(res_sn["stdout"])
    write_json(outdir / "ec2_describe_subnets_public.json", subnets)
    ok_sn = res_sn["rc"] == 0 and len(subnets.get("Subnets", [])) >= 2

    # Route tables con default route a IGW
    res_rt = run(f'aws ec2 describe-route-tables --region {REGION}')
    rts = parse_json_or_raw(res_rt["stdout"])
    write_json(outdir / "ec2_describe_route_tables.json", rts)
    ok_rt = False
    for rt in rts.get("RouteTables", []):
        for r in rt.get("Routes", []):
            if r.get("DestinationCidrBlock") == "0.0.0.0/0" and r.get("GatewayId", "").startswith("igw-"):
                ok_rt = True
                break

    overall = ok_vpc and ok_igw and ok_sn and ok_rt
    return {"name": "Network(VPC/IGW/Subnets/Route)", "status": status(overall),
            "detail": {"vpc": ok_vpc, "igw": ok_igw, "subnets>=2": ok_sn, "route_to_igw": ok_rt}}

def check_eks_cluster(outdir: Path) -> Dict[str, Any]:
    res = run(f"aws eks describe-cluster --name {CLUSTER_NAME} --region {REGION}")
    data = parse_json_or_raw(res["stdout"])
    write_json(outdir / "eks_describe_cluster.json", data)
    cluster_ok = res["rc"] == 0 and data.get("cluster", {}).get("status") == "ACTIVE"

    # Access entries (opcional: listar todos y buscar principal root y rol OIDC)
    res_acc = run(f"aws eks list-access-entries --cluster-name {CLUSTER_NAME} --region {REGION}")
    acc = parse_json_or_raw(res_acc["stdout"])
    write_json(outdir / "eks_list_access_entries.json", acc)
    # Marcar como ok si hay al menos uno; validación estricta puede ajustarse:
    have_acc = res_acc["rc"] == 0 and len(acc.get("accessEntries", [])) >= 1

    return {"name": "EKSCluster", "status": status(cluster_ok and have_acc),
            "detail": {"cluster_active": cluster_ok, "access_entries>=1": have_acc}}

def check_eks_nodegroups(outdir: Path) -> Dict[str, Any]:
    # Listar nodegroups
    res_list = run(f"aws eks list-nodegroups --cluster-name {CLUSTER_NAME} --region {REGION}")
    lst = parse_json_or_raw(res_list["stdout"])
    write_json(outdir / "eks_list_nodegroups.json", lst)

    ok_list = res_list["rc"] == 0 and lst.get("nodegroups")
    active_ok = False
    details: List[Dict[str, Any]] = []

    if ok_list:
        for ng in lst["nodegroups"]:
            res_desc = run(f"aws eks describe-nodegroup --cluster-name {CLUSTER_NAME} --nodegroup-name {ng} --region {REGION}")
            desc = parse_json_or_raw(res_desc["stdout"])
            write_json(outdir / f"eks_describe_nodegroup_{ng}.json", desc)
            st = desc.get("nodegroup", {}).get("status")
            issues = desc.get("nodegroup", {}).get("health", {}).get("issues", [])
            details.append({"name": ng, "status": st, "issues": issues})
            if st == "ACTIVE":
                active_ok = True

    return {"name": "EKSNodeGroups", "status": status(ok_list and active_ok),
            "detail": {"listed": ok_list, "any_active": active_ok, "nodegroups": details}}

def check_iam_oidc_and_roles(outdir: Path) -> Dict[str, Any]:
    # OIDC providers (GitHub y EKS OIDC)
    res_oidc = run("aws iam list-open-id-connect-providers")
    oidc = parse_json_or_raw(res_oidc["stdout"])
    write_json(outdir / "iam_list_open_id_connect_providers.json", oidc)
    ok_oidc = res_oidc["rc"] == 0 and isinstance(oidc, dict)

    # Rol de GitHub Actions (si seguimos el nombre de Terraform)
    role_name = "fastticket-GitHubOIDC"
    res_role = run(f"aws iam get-role --role-name {role_name}")
    role = parse_json_or_raw(res_role["stdout"])
    write_json(outdir / "iam_get_role_github_actions.json", role)
    ok_role = res_role["rc"] == 0 and role.get("Role", {}).get("RoleName") == role_name

    # Policy mínima adjunta (nombre de ejemplo)
    policy_name = "fastticket-gha-eks-min"
    res_policies = run("aws iam list-policies --scope Local")
    pol = parse_json_or_raw(res_policies["stdout"])
    write_json(outdir / "iam_list_policies_local.json", pol)

    ok_policy = False
    if isinstance(pol, dict):
        # Algunos AWS CLI devuelven bajo "Policies", otros puede que no; validar flexible
        policies = pol.get("Policies") or pol.get("raw")
        if isinstance(policies, list):
            ok_policy = any(p.get("PolicyName") == policy_name for p in policies)
        # si "raw" es str/json en otro formato, el usuario podría adaptar aquí

    return {"name": "IAM(OIDC/Role/Policy)", "status": status(ok_oidc and ok_role),
            "detail": {"oidc_list_ok": ok_oidc, "role_found": ok_role, "policy_found_hint": ok_policy}}

def check_instance_inventory(outdir: Path) -> Dict[str, Any]:
    # Instancias EC2 etiquetadas por el cluster
    res = run(f'aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values={CLUSTER_NAME}" --region {REGION}')
    data = parse_json_or_raw(res["stdout"])
    write_json(outdir / "ec2_describe_instances_by_cluster.json", data)

    instances = []
    for r in data.get("Reservations", []):
        for i in r.get("Instances", []):
            instances.append({
                "Id": i.get("InstanceId"),
                "Type": i.get("InstanceType"),
                "AZ": i.get("Placement", {}).get("AvailabilityZone"),
                "State": i.get("State", {}).get("Name"),
                "PublicIp": i.get("PublicIpAddress"),
            })
    ok = res["rc"] == 0 and len(instances) >= 1
    return {"name": "EC2InstancesForCluster", "status": status(ok), "detail": {"instances": instances}}

def check_kubectl(outdir: Path) -> Dict[str, Any]:
    # Opcional: si kubectl está disponible, validamos acceso
    if not which("kubectl"):
        return {"name": "KubectlPresence", "status": "SKIP", "detail": "kubectl not found in PATH"}

    # Actualizar kubeconfig (no falla si ya existe)
    _ = run(f"aws eks update-kubeconfig --region {REGION} --name {CLUSTER_NAME}")

    # Healthz (algunos clusters requieren auth; si falla, lo registramos)
    res_h = run("kubectl get --raw=/healthz", timeout=30)
    write_text(outdir / "kubectl_healthz.txt", f"rc={res_h['rc']}\nstdout={res_h['stdout']}\nstderr={res_h['stderr']}\n")
    ok_health = res_h["rc"] == 0 and "ok" in res_h["stdout"].lower()

    # Nodes
    res_n = run("kubectl get nodes -o json", timeout=60)
    nodes = parse_json_or_raw(res_n["stdout"])
    write_json(outdir / "kubectl_get_nodes.json", nodes)

    nodes_ready = False
    if isinstance(nodes, dict):
        for item in nodes.get("items", []):
            for cond in item.get("status", {}).get("conditions", []):
                if cond.get("type") == "Ready" and cond.get("status") == "True":
                    nodes_ready = True
                    break

    overall = ok_health and nodes_ready
    return {"name": "KubeAPI/Nodelist", "status": status(overall),
            "detail": {"healthz_ok": ok_health, "any_node_ready": nodes_ready, "kubectl_rc": res_n["rc"]}}

# ---------------------------
# MAIN
# ---------------------------
def main():
    ts = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    outdir = BASE_OUTDIR / ts
    outdir.mkdir(parents=True, exist_ok=True)

    meta = {
        "region": REGION,
        "cluster_name": CLUSTER_NAME,
        "project_tag": PROJECT_TAG,
        "account_id": ACCOUNT_ID,
        "timestamp_utc": ts,
    }
    write_json(outdir / "meta.json", meta)

    checks = []
    checks.append(check_sts(outdir))
    checks.append(check_vpc(outdir))
    checks.append(check_eks_cluster(outdir))
    checks.append(check_eks_nodegroups(outdir))
    checks.append(check_iam_oidc_and_roles(outdir))
    checks.append(check_instance_inventory(outdir))
    checks.append(check_kubectl(outdir))

    # Resumen final
    summary = {
        "meta": meta,
        "checks": checks,
        "overall": "PASS" if all(c["status"] in ("PASS", "SKIP") for c in checks) else "FAIL"
    }
    write_json(outdir / "summary.json", summary)

    print(f"\nValidation completed. Output directory: {outdir}\nOverall: {summary['overall']}")
    for c in checks:
        print(f"- {c['name']}: {c['status']}")

if __name__ == "__main__":
    # Permitir override por argv simples: python3 validate_tf_aws.py us-east-1 fastticket-eks fastticket 6655...
    if len(sys.argv) >= 2:
        globals()["REGION"] = sys.argv[1]
    if len(sys.argv) >= 3:
        globals()["CLUSTER_NAME"] = sys.argv[2]
    if len(sys.argv) >= 4:
        globals()["PROJECT_TAG"] = sys.argv[3]
    if len(sys.argv) >= 5:
        globals()["ACCOUNT_ID"] = sys.argv[4]
    main()
