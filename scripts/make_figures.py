"""
Generate paper figures from artefacts in Documentation/eval_artifacts/.

Outputs to Documentation/figures/:
  - confusion_matrix.png   (from classification on held-out test split)
  - feature_importance.png (XGBoost gain importance)
  - latency_overhead.png   (bar chart, baseline vs rules vs ai)
  - architecture.png       (lightweight box diagram)

ROC and per-class F1 plots are skipped if class support is too small.
"""
import json
import csv
import sys
from pathlib import Path

import numpy as np
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "Documentation" / "eval_artifacts"
FIG = ROOT / "Documentation" / "figures"
FIG.mkdir(parents=True, exist_ok=True)

# ---------- 1. Confusion matrix + feature importance from training ----------
def figs_from_training():
    rep_path = ART / "training_report.json"
    if not rep_path.exists():
        print(f"  skip: {rep_path} not found (run train_and_export.py first)")
        return
    rep = json.loads(rep_path.read_text())

    # Confusion matrix
    cm = np.array(rep["confusion_matrix"])
    labels = rep["labels"]
    fig, ax = plt.subplots(figsize=(6.5, 5.5))
    im = ax.imshow(cm, cmap="Blues")
    ax.set_xticks(range(len(labels)))
    ax.set_yticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=35, ha="right")
    ax.set_yticklabels(labels)
    ax.set_xlabel("Predicted")
    ax.set_ylabel("True")
    ax.set_title("XGBoost confusion matrix (held-out 20% test split)")
    for i in range(cm.shape[0]):
        for j in range(cm.shape[1]):
            ax.text(j, i, str(cm[i, j]), ha="center", va="center",
                    color="white" if cm[i, j] > cm.max() * 0.5 else "black",
                    fontsize=10)
    fig.colorbar(im, ax=ax)
    fig.tight_layout()
    fig.savefig(FIG / "confusion_matrix.png", dpi=150)
    plt.close(fig)
    print(f"  wrote {FIG / 'confusion_matrix.png'}")

    # Feature importance
    imp = rep.get("feature_importance")
    if imp:
        items = sorted(imp.items(), key=lambda kv: kv[1], reverse=True)
        names = [k for k, _ in items]
        vals = [v for _, v in items]
        fig, ax = plt.subplots(figsize=(7, 5))
        ax.barh(names[::-1], vals[::-1], color="#1f77b4")
        ax.set_xlabel("Gain")
        ax.set_title("XGBoost feature importance (gain)")
        fig.tight_layout()
        fig.savefig(FIG / "feature_importance.png", dpi=150)
        plt.close(fig)
        print(f"  wrote {FIG / 'feature_importance.png'}")


# ---------- 2. Latency overhead ----------
def fig_latency():
    csv_path = ART / "latency_runs.csv"
    if not csv_path.exists():
        print(f"  skip: {csv_path} not found")
        return
    df = pd.read_csv(csv_path)
    df = df[df["ms"] > 0]
    grp = df.groupby("label")["ms"].agg(["mean", lambda s: np.percentile(s, 95),
                                          lambda s: np.percentile(s, 99), "count"])
    grp.columns = ["mean", "p95", "p99", "n"]
    ordering = [l for l in ["baseline", "rules", "ai"] if l in grp.index]
    grp = grp.loc[ordering]
    print(grp.round(2).to_string())

    x = np.arange(len(grp.index))
    w = 0.27
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(x - w, grp["mean"], width=w, label="mean")
    ax.bar(x,     grp["p95"],  width=w, label="p95")
    ax.bar(x + w, grp["p99"],  width=w, label="p99")
    ax.set_xticks(x)
    ax.set_xticklabels(grp.index)
    ax.set_ylabel("Latency (ms)")
    ax.set_title("End-to-end request latency by detection mode")
    ax.legend()
    fig.tight_layout()
    fig.savefig(FIG / "latency_overhead.png", dpi=150)
    plt.close(fig)
    print(f"  wrote {FIG / 'latency_overhead.png'}")

    # save the summary as csv too for the paper
    grp.round(3).to_csv(ART / "latency_summary.csv")


# ---------- 3. Architecture diagram ----------
def fig_architecture():
    fig, ax = plt.subplots(figsize=(11, 6.5))
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 65)
    ax.axis("off")

    def box(x, y, w, h, label, fc="#dde6f3", ec="#1f3a5f", fontsize=9):
        ax.add_patch(plt.Rectangle((x, y), w, h, fc=fc, ec=ec, lw=1.5))
        ax.text(x + w / 2, y + h / 2, label, ha="center", va="center", fontsize=fontsize)

    # K8s cluster outer
    ax.add_patch(plt.Rectangle((2, 8), 60, 52, fill=False, ec="#444", ls="--", lw=1.2))
    ax.text(4, 58, "Kubernetes (minikube) + Istio service mesh", fontsize=10, weight="bold")

    # Bookinfo pods + Envoy
    for i, name in enumerate(["productpage", "details", "reviews", "ratings"]):
        box(5 + i * 13, 42, 12, 8, f"{name}\n+ Envoy", fc="#fbeacb")

    ax.text(33, 38.5, "Envoy access logs (JSON)", ha="center", fontsize=8, style="italic")
    ax.annotate("", xy=(33, 30), xytext=(33, 41),
                arrowprops=dict(arrowstyle="->", color="#1f3a5f"))

    # Zentrion orchestrator
    box(8, 18, 50, 12,
        "Zentrion Orchestrator (NestJS pod)\n"
        "telemetry watcher → rule engine + ML detector →\n"
        "policy generator → K8s API client (applies AuthorizationPolicy)",
        fc="#d4e4d4")

    # Postgres
    box(8, 9, 22, 6, "PostgreSQL\n(telemetry / anomalies /\npolicy_drafts)", fc="#e8d8f3", fontsize=8)
    # CRDs
    box(36, 9, 22, 6, "CRDs\nSecurityProfile / AnomalyRecord /\nPolicyHistory", fc="#e8d8f3", fontsize=8)

    # External services (host)
    box(66, 42, 30, 8, "FastAPI ML service\n(XGBoost • joblib)", fc="#f4d4d4")
    box(66, 30, 30, 8, "Ollama container\n(qwen2.5:7b)\nLLM explanations", fc="#f4d4d4")
    ax.annotate("", xy=(66, 24), xytext=(58, 24),
                arrowprops=dict(arrowstyle="->", color="#1f3a5f"))
    ax.text(62, 25.5, "HTTP", fontsize=8, ha="center")

    # Dashboard
    box(66, 18, 30, 8, "Next.js Dashboard\nWebSocket + REST + HITL approval", fc="#d4e4f4")
    ax.annotate("", xy=(66, 22), xytext=(58, 22),
                arrowprops=dict(arrowstyle="<->", color="#1f3a5f"))
    ax.text(62, 23.5, "API/WS", fontsize=8, ha="center")

    ax.set_title("Zentrion system architecture", fontsize=13, weight="bold")
    fig.tight_layout()
    fig.savefig(FIG / "architecture.png", dpi=150)
    plt.close(fig)
    print(f"  wrote {FIG / 'architecture.png'}")


if __name__ == "__main__":
    print("[figs] training-derived...")
    figs_from_training()
    print("[figs] latency...")
    fig_latency()
    print("[figs] architecture...")
    fig_architecture()
    print("[figs] done.")
