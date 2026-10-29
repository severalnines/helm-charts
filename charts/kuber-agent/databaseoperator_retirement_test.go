package chart_test

import (
	"bytes"
	"fmt"
	"github.com/stretchr/testify/require"
	"io"
	rbacv1 "k8s.io/api/rbac/v1"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
	"os/exec"
	"strings"
	"testing"
)

func TestRetirementRBACIsLimitedToReleasedMirrorInBothModes(t *testing.T) {
	// The subject must follow the chart's namespace helper, so a
	// namespaceOverride install binds the ServiceAccount that actually exists.
	for _, override := range []string{"", "workload"} {
		for _, write := range []bool{false, true} {
			t.Run(fmt.Sprintf("write=%t/override=%q", write, override), func(t *testing.T) {
				args := []string{"template", "retirement", ".", "--namespace", "control", "--set", fmt.Sprintf("mode.write.enabled=%t", write), "--set", "rbac.serviceAccounts.agent.name=test-reader", "--set", "rbac.serviceAccounts.write.name=test-writer"}
				wantNamespace := "control"
				if override != "" {
					args = append(args, "--set", "namespaceOverride="+override)
					wantNamespace = override
				}
				output, err := exec.Command("helm", args...).CombinedOutput()
				require.NoError(t, err, string(output))
				decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
				role, binding := false, false
				for {
					var doc struct {
						renderedRBAC
						Subjects []rbacv1.Subject `json:"subjects"`
					}
					err := decoder.Decode(&doc)
					if err == io.EOF {
						break
					}
					require.NoError(t, err)
					if !strings.HasSuffix(doc.Metadata.Name, "-databaseoperator-retirement") {
						continue
					}
					switch doc.Kind {
					case "ClusterRole":
						role = true
						require.Equal(t, []rbacv1.PolicyRule{
							{APIGroups: []string{"apiextensions.k8s.io"}, Resources: []string{"customresourcedefinitions"}, ResourceNames: []string{"databaseoperators.agent.severalnines.com"}, Verbs: []string{"get", "delete"}},
							{APIGroups: []string{"agent.severalnines.com"}, Resources: []string{"databaseoperators"}, Verbs: []string{"list", "patch", "delete"}},
						}, doc.Rules)
					case "ClusterRoleBinding":
						binding = true
						want := "test-reader"
						if write {
							want = "test-writer"
						}
						require.Equal(t, []rbacv1.Subject{{Kind: "ServiceAccount", Name: want, Namespace: wantNamespace}}, doc.Subjects)
						require.Equal(t, "ClusterRole", doc.RoleRef.Kind)
						require.Equal(t, doc.Metadata.Name, doc.RoleRef.Name)
					}
				}
				require.True(t, role)
				require.True(t, binding)
			})
		}
	}
}
