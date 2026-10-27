package chart_test

import (
	"bytes"
	"fmt"
	"io"
	"os/exec"
	"testing"

	"github.com/stretchr/testify/require"
	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

func TestControllerRolloutDoesNotOverlapUnelectedManagers(t *testing.T) {
	for _, tc := range []struct {
		replicas int
		election bool
		recreate bool
	}{{1, false, true}, {1, true, false}, {2, false, false}, {2, true, false}} {
		t.Run(fmt.Sprintf("replicas=%d/election=%t", tc.replicas, tc.election), func(t *testing.T) {
			output, err := exec.Command("helm", "template", "rollout", ".", "--namespace", "operator", "--set", fmt.Sprintf("controllerManager.replicas=%d", tc.replicas), "--set", fmt.Sprintf("controllerManager.leaderElect=%t", tc.election)).CombinedOutput()
			require.NoError(t, err, string(output))
			decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
			found := false
			for {
				var object unstructured.Unstructured
				err := decoder.Decode(&object.Object)
				if err == io.EOF {
					break
				}
				require.NoError(t, err)
				if object.GetKind() != "Deployment" || object.GetLabels()["control-plane"] != "controller-manager" {
					continue
				}
				var dep appsv1.Deployment
				require.NoError(t, runtime.DefaultUnstructuredConverter.FromUnstructured(object.Object, &dep))
				found = true
				require.Equal(t, tc.recreate, dep.Spec.Strategy.Type == appsv1.RecreateDeploymentStrategyType)
				var args []string
				for _, container := range dep.Spec.Template.Spec.Containers {
					if container.Name == "manager" {
						args = container.Args
					}
				}
				require.NotEmpty(t, args)
				if tc.recreate {
					require.NotContains(t, args, "--leader-elect")
					strategy, _, err := unstructured.NestedMap(object.Object, "spec", "strategy")
					require.NoError(t, err)
					require.Contains(t, strategy, "rollingUpdate", "upgrade must explicitly clear the old rolling-update defaults")
					require.Nil(t, strategy["rollingUpdate"])
				} else {
					require.Contains(t, args, "--leader-elect", "rolling overlap requires an elected writer")
				}
			}
			require.True(t, found)
		})
	}
}
