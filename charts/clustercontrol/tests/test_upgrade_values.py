"""Render the chart with the values Helm --reuse-values actually makes available.

Run after `helm dependency build charts/clustercontrol`:
python3 -m unittest discover -s charts/clustercontrol/tests -v
Requires Helm and PyYAML. No Kubernetes cluster or credentials are used.
"""

import copy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


CHART = Path(__file__).resolve().parents[1]


class UpgradeValuesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cc-upgrade-values-")
        self.addCleanup(self.temp.cleanup)
        self.chart = Path(self.temp.name) / "clustercontrol"
        shutil.copytree(CHART, self.chart, ignore=shutil.ignore_patterns("tests"))
        self.current = yaml.safe_load((CHART / "values.yaml").read_text())

    def old_values(self, version="0.4.0"):
        return yaml.safe_load(
            (CHART / "tests" / "fixtures" / f"{version}-values.yaml").read_text()
        )

    def render(self, values):
        # Passing old values with -f would merge NEW chart defaults and conceal
        # the regression. Replace values.yaml to model Helm reusing OLD defaults.
        (self.chart / "values.yaml").write_text(yaml.safe_dump(values))
        result = subprocess.run(
            ["helm", "template", "cc", str(self.chart), "--is-upgrade"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return [doc for doc in yaml.safe_load_all(result.stdout) if doc]

    def resource(self, docs, kind, name):
        return next(d for d in docs if d["kind"] == kind and d["metadata"]["name"] == name)

    def pod(self, docs):
        return self.resource(docs, "StatefulSet", "cmon-master")["spec"]["template"]["spec"]

    def init(self, docs):
        return next(c for c in self.pod(docs)["initContainers"] if c["name"] == "init-ccmgr")["command"][-1]

    def test_old_releases_get_new_defaults(self):
        for version in ("0.3.0", "0.4.0"):
            with self.subTest(version=version):
                docs = self.render(self.old_values(version))
                service = self.resource(docs, "Service", "cmon-master-public")["spec"]
                self.assertEqual(service["type"], "LoadBalancer")
                self.assertEqual({p["name"]: p["port"] for p in service["ports"]},
                                 {"https": 443, "http": 80, "kuber-proxy-grpc": 50051})
                self.assertIn("--set acme_enabled=false", self.init(docs))
                self.assertFalse(any(d["kind"] == "Ingress" for d in docs))

    def test_fallbacks_match_current_chart_defaults(self):
        (self.chart / "templates" / "test-defaults.yaml").write_text('''
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-defaults
data:
  publicService: {{ include "cc.publicService" . | quote }}
  tls: {{ include "cc.tls" . | quote }}
''')
        docs = self.render(self.old_values())
        data = self.resource(docs, "ConfigMap", "test-defaults")["data"]
        self.assertEqual(yaml.safe_load(data["publicService"]), self.current["publicService"])
        self.assertEqual(yaml.safe_load(data["tls"]), self.current["cmon"]["tls"])

    def test_missing_tls_independently(self):
        values = copy.deepcopy(self.current)
        del values["cmon"]["tls"]
        self.assertIn("--set acme_enabled=false", self.init(self.render(values)))

    def test_explicit_false_and_zero_survive(self):
        values = self.old_values()
        values["publicService"] = {"enabled": False}
        docs = self.render(values)
        self.assertFalse(any(d["metadata"]["name"] == "cmon-master-public" for d in docs))
        values["publicService"] = {"ports": {"http": 0, "grpc": 0, "cmon": 0}}
        service = self.resource(self.render(values), "Service", "cmon-master-public")
        self.assertEqual([p["name"] for p in service["spec"]["ports"]], ["https"])

    def test_partial_nodeport_and_existing_overrides(self):
        values = self.old_values()
        values["cmon"]["image"] = "example.invalid/cmon:preserved"
        values["publicService"] = {"type": "NodePort", "nodePorts": {"https": 30443},
                                   "annotations": {"example.com/preserved": "yes"}}
        docs = self.render(values)
        service = self.resource(docs, "Service", "cmon-master-public")
        self.assertEqual(service["spec"]["type"], "NodePort")
        self.assertEqual(service["spec"]["ports"][0]["nodePort"], 30443)
        self.assertEqual(service["metadata"]["annotations"]["example.com/preserved"], "yes")
        cmon = next(c for c in self.pod(docs)["containers"] if c["name"] == "cmon-master")
        self.assertEqual(cmon["image"], "example.invalid/cmon:preserved")

    def test_partial_acme_uses_defaults_and_keeps_overrides(self):
        values = self.old_values()
        values["fqdn"] = "cc.example.com"
        values["cmon"]["tls"] = {"mode": "acme"}
        command = self.init(self.render(values))
        self.assertIn('--set acme_domains="cc.example.com"', command)
        self.assertIn("--set acme_staging=false", command)
        self.assertIn("/autocert-cache/production", command)
        values["cmon"]["tls"]["acme"] = {"staging": True, "domains": ["other.example.com"]}
        command = self.init(self.render(values))
        self.assertIn('--set acme_domains="other.example.com"', command)
        self.assertIn("/autocert-cache/staging", command)

    def test_custom_tls_mounts_supplied_secret(self):
        values = self.old_values()
        values["cmon"]["tls"] = {"mode": "custom", "custom": {"secretName": "existing-tls"}}
        docs = self.render(values)
        volume = next(v for v in self.pod(docs)["volumes"] if v["name"] == "ccmgr-tls")
        self.assertEqual(volume["secret"]["secretName"], "existing-tls")
        self.assertIn("--set acme_enabled=false", self.init(docs))

    def test_fresh_defaults_still_render(self):
        docs = self.render(self.current)
        self.assertEqual(self.resource(docs, "Service", "cmon-master-public")["spec"]["type"],
                         "LoadBalancer")
