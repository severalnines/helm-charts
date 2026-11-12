package chart_test

import (
	"bytes"
	"fmt"
	"github.com/severalnines/clustercontrol-k8s/agent-operator/internal/addon"
	"github.com/severalnines/clustercontrol-k8s/agent-operator/internal/addon/gateway"
	"io"
	"os/exec"
	"slices"
	"testing"

	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

type renderedRBAC struct {
	Kind     string              `json:"kind"`
	Metadata metav1.ObjectMeta   `json:"metadata"`
	Rules    []rbacv1.PolicyRule `json:"rules"`
	RoleRef  rbacv1.RoleRef      `json:"roleRef"`
}

func permits(rules []rbacv1.PolicyRule, group, resource, verb string) bool {
	for _, rule := range rules {
		if (slices.Contains(rule.APIGroups, group) || slices.Contains(rule.APIGroups, "*")) && (slices.Contains(rule.Resources, resource) || slices.Contains(rule.Resources, "*")) && (slices.Contains(rule.Verbs, verb) || slices.Contains(rule.Verbs, "*")) {
			return true
		}
	}
	return false
}

func TestGatewayInventoryReadPermissionsKeepExistingGrantBoundaries(t *testing.T) {
	for _, write := range []bool{false, true} {
		t.Run(fmt.Sprint(write), func(t *testing.T) {
			cmd := exec.Command("helm", "template", "inventory-rbac", ".", "--namespace", "severalnines-system", "--set", fmt.Sprintf("mode.write.enabled=%t", write), "--set", "rbac.clusterRead.includeSecrets=false", "--set", "rbac.namespaces.targets={envoy-gateway-system}")
			output, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("render chart: %v: %s", err, output)
			}
			decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
			roles := map[string][]rbacv1.PolicyRule{}
			extraBound, globalWrite := false, false
			for {
				var doc renderedRBAC
				err := decoder.Decode(&doc)
				if err == io.EOF {
					break
				}
				if err != nil {
					t.Fatal(err)
				}
				if doc.Kind == "ClusterRole" {
					roles[doc.Metadata.Name] = doc.Rules
				}
				if doc.Kind == "ClusterRoleBinding" {
					if doc.RoleRef.Name == "s9s:cluster-read-extra" {
						t.Fatal("read-extra gained an unrequested global binding")
					}
					if doc.RoleRef.Name == "s9s:cluster-write" {
						globalWrite = true
					}
				}
				if doc.Kind == "RoleBinding" && doc.RoleRef.Name == "s9s:cluster-read-extra" && doc.Metadata.Namespace == "envoy-gateway-system" {
					extraBound = true
				}
			}
			if !extraBound || globalWrite != write {
				t.Fatalf("grant boundaries changed: extra=%v globalWrite=%v", extraBound, globalWrite)
			}
			// Cross-check the actual addon render in every supported mode;
			// a newly emitted kind must acquire an explicit reviewed read path.
			readPaths := map[string]struct{ resource, role string }{
				"/Namespace":                             {"namespaces", "s9s:cluster-read"},
				"agent.severalnines.com/AppBundle":       {"appbundles", "s9s:cluster-read"},
				"rbac.authorization.k8s.io/RoleBinding":  {"rolebindings", "s9s:cluster-read"},
				"gateway.networking.k8s.io/GatewayClass": {"gatewayclasses", "s9s:cluster-read"},
				"gateway.networking.k8s.io/Gateway":      {"gateways", "s9s:cluster-read"},
				"gateway.envoyproxy.io/EnvoyProxy":       {"envoyproxies", "s9s:cluster-read-extra"},
				"cert-manager.io/Issuer":                 {"issuers", "s9s:cluster-read"},
				"cert-manager.io/Certificate":            {"certificates", "s9s:cluster-read"},
			}
			for _, implementation := range []string{gateway.ImplementationEnvoy, gateway.ImplementationExternal} {
				for _, certMode := range []string{gateway.CertModeSelfSigned, gateway.CertModeACME, gateway.CertModeCustomSecret} {
					cfg := gateway.Config{Enabled: true, Implementation: implementation, ChartVersion: "v1.8.2", ServiceType: "LoadBalancer", CertMode: certMode, Hostname: "gateway.example.test", CertSecretName: "tls-fixture"}
					if implementation == gateway.ImplementationExternal {
						cfg.ClassName = "customer"
					}
					objects, err := gateway.NewWithConfig(cfg).Resources(addon.Config{AgentNamespace: "severalnines-system"})
					if err != nil {
						t.Fatal(err)
					}
					for _, object := range objects {
						gvk := object.GroupVersionKind()
						scope, found := readPaths[gvk.Group+"/"+gvk.Kind]
						if !found {
							t.Fatalf("gateway kind %s has no reviewed read path", gvk)
						}
						for _, verb := range []string{"get", "list", "watch"} {
							if !permits(roles[scope.role], gvk.Group, scope.resource, verb) {
								t.Errorf("%s lacks %s on %s", scope.role, verb, gvk)
							}
						}
					}
				}
			}
			// Native primary observation and routes emitted by exposure and
			// observability are outside the gateway aux render but use its edge.
			for _, item := range []struct{ group, resource string }{
				{"argoproj.io", "applications"},
				{"gateway.networking.k8s.io", "httproutes"},
				{"gateway.networking.k8s.io", "tcproutes"},
				{"gateway.networking.k8s.io", "listenersets"},
				{"apiextensions.k8s.io", "customresourcedefinitions"},
				{"apps", "deployments"},
				{"", "services"}, {"", "pods"}, {"", "nodes"},
			} {
				for _, verb := range []string{"get", "list", "watch"} {
					if !permits(roles["s9s:cluster-read"], item.group, item.resource, verb) {
						t.Errorf("base read lacks %s %s/%s", verb, item.group, item.resource)
					}
				}
			}

			// Certificate definitions are base-readable; keys and EnvoyProxy
			// configuration retain the existing namespace-extra boundary.
			for _, item := range []struct {
				group, resource                string
				baseRead, extraRead, writeRead bool
			}{
				{"cert-manager.io", "issuers", true, false, true},
				{"cert-manager.io", "certificates", true, false, true},
				{"gateway.envoyproxy.io", "envoyproxies", false, true, true},
				{"", "secrets", false, true, false},
			} {
				for _, verb := range []string{"get", "list", "watch"} {
					for _, expected := range []struct {
						role    string
						allowed bool
					}{
						{"s9s:cluster-read", item.baseRead},
						{"s9s:cluster-read-extra", item.extraRead},
						{"s9s:cluster-write", item.writeRead},
					} {
						if got := permits(roles[expected.role], item.group, item.resource, verb); got != expected.allowed {
							t.Errorf("%s %s %s/%s = %v, want %v", expected.role, verb, item.group, item.resource, got, expected.allowed)
						}
					}
				}
				for _, verb := range []string{"create", "update", "patch", "delete"} {
					for _, role := range []string{"s9s:cluster-read", "s9s:cluster-read-extra"} {
						if permits(roles[role], item.group, item.resource, verb) {
							t.Fatalf("%s gained %s %s/%s", role, verb, item.group, item.resource)
						}
					}
					if !permits(roles["s9s:cluster-write"], item.group, item.resource, verb) {
						t.Fatalf("existing write permission lost: %s %s/%s", verb, item.group, item.resource)
					}
				}
			}

			for _, role := range []string{"s9s:cluster-read", "s9s:cluster-read-extra", "s9s:cluster-write"} {
				for _, rule := range roles[role] {
					if (slices.Contains(rule.APIGroups, "cert-manager.io") || slices.Contains(rule.APIGroups, "gateway.envoyproxy.io")) && len(rule.ResourceNames) != 0 {
						t.Fatalf("%s cannot perform owned inventory lists with resourceNames restrictions", role)
					}
					if slices.Contains(rule.Verbs, "*") || slices.Contains(rule.Verbs, "bind") || slices.Contains(rule.Verbs, "escalate") || slices.Contains(rule.Resources, "*") || slices.Contains(rule.APIGroups, "*") {
						t.Fatalf("unbounded permission in %s", role)
					}
				}
			}
		})
	}
}

func TestPrometheusAgentInventoryReadSplit(t *testing.T) {
	for _, write := range []bool{false, true} {
		output, err := exec.Command("helm", "template", "prometheus-inventory", ".", "--set", fmt.Sprintf("mode.write.enabled=%t", write), "--set", "rbac.clusterRead.includeSecrets=false").CombinedOutput()
		if err != nil {
			t.Fatalf("render: %v: %s", err, output)
		}
		roles := map[string][]rbacv1.PolicyRule{}
		decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
		for {
			var obj renderedRBAC
			err := decoder.Decode(&obj)
			if err == io.EOF {
				break
			}
			if err != nil {
				t.Fatal(err)
			}
			if obj.Kind == "ClusterRole" {
				roles[obj.Metadata.Name] = obj.Rules
			}
		}
		for _, item := range []struct{ group, resource, role string }{
			{"rbac.authorization.k8s.io", "clusterroles", "s9s:cluster-read"},
			{"rbac.authorization.k8s.io", "clusterrolebindings", "s9s:cluster-read"},
			{"monitoring.coreos.com", "prometheusagents", "s9s:cluster-read-extra"},
		} {
			for _, verb := range []string{"get", "list", "watch"} {
				for _, role := range []string{"s9s:cluster-read", "s9s:cluster-read-extra"} {
					if got := permits(roles[role], item.group, item.resource, verb); got != (role == item.role) {
						t.Errorf("%s %s %s/%s = %t", role, verb, item.group, item.resource, got)
					}
				}
			}
			for _, verb := range []string{"create", "update", "patch", "delete", "bind", "escalate"} {
				for _, role := range []string{"s9s:cluster-read", "s9s:cluster-read-extra"} {
					if permits(roles[role], item.group, item.resource, verb) {
						t.Errorf("%s must not %s %s/%s", role, verb, item.group, item.resource)
					}
				}
			}
		}
	}
}
