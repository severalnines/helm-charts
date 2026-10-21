package chart_test

import (
	"bytes"
	"fmt"
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
			for _, item := range []struct{ group, resource string }{{"cert-manager.io", "issuers"}, {"cert-manager.io", "certificates"}, {"gateway.envoyproxy.io", "envoyproxies"}} {
				for _, verb := range []string{"get", "list", "watch"} {
					if permits(roles["s9s:cluster-read"], item.group, item.resource, verb) {
						t.Fatalf("global read role widened for %s/%s", item.group, item.resource)
					}
					for _, role := range []string{"s9s:cluster-read-extra", "s9s:cluster-write"} {
						if !permits(roles[role], item.group, item.resource, verb) {
							t.Errorf("%s lacks %s %s/%s", role, verb, item.group, item.resource)
						}
					}
				}
				for _, verb := range []string{"create", "update", "patch", "delete"} {
					if permits(roles["s9s:cluster-read-extra"], item.group, item.resource, verb) {
						t.Fatalf("read-extra gained %s", verb)
					}
					if !permits(roles["s9s:cluster-write"], item.group, item.resource, verb) {
						t.Fatalf("existing write permission lost: %s", verb)
					}
				}
			}
			for _, role := range []string{"s9s:cluster-read-extra", "s9s:cluster-write"} {
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
