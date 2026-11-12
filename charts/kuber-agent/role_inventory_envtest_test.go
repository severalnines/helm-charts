package chart_test

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
	"slices"
	"testing"
	"time"

	"github.com/severalnines/clustercontrol-k8s/kubercc/delivery"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apiextv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
)

func TestRestrictedRoleInventoryDoesNotGrantSecretAccess(t *testing.T) {
	output, err := exec.Command("helm", "template", "role-inventory", ".", "--namespace", "control", "--set", "mode.write.enabled=false", "--set", "rbac.clusterRead.includeSecrets=false").CombinedOutput()
	require.NoError(t, err, "%s", output)
	decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
	var role, extraRole *rbacv1.ClusterRole
	for {
		object := &unstructured.Unstructured{}
		err := decoder.Decode(&object.Object)
		if err == io.EOF {
			break
		}
		require.NoError(t, err)
		if object.GetKind() == "ClusterRole" && object.GetName() == "s9s:cluster-read" {
			role = &rbacv1.ClusterRole{}
			require.NoError(t, runtime.DefaultUnstructuredConverter.FromUnstructured(object.Object, role))
		}
		if object.GetKind() == "ClusterRole" && object.GetName() == "s9s:cluster-read-extra" {
			extraRole = &rbacv1.ClusterRole{}
			require.NoError(t, runtime.DefaultUnstructuredConverter.FromUnstructured(object.Object, extraRole))
		}
	}
	require.NotNil(t, role)
	require.NotNil(t, extraRole)
	for _, rule := range role.Rules {
		require.NotContains(t, rule.Resources, "secrets")
		require.NotContains(t, rule.Resources, "*")
		for _, verb := range rule.Verbs {
			require.True(t, slices.Contains([]string{"get", "list", "watch"}, verb), "unexpected read-policy verb %s", verb)
		}
	}
	if os.Getenv("KUBEBUILDER_ASSETS") == "" {
		if os.Getenv("CI") != "" {
			t.Fatal("CI must supply envtest assets")
		}
		t.Skip("set KUBEBUILDER_ASSETS for restricted Role inventory API test")
	}
	env := &envtest.Environment{}
	// Minimal served schemas exercise real API authorization, not native validation
	// or reconciliation. EnvoyProxy deliberately remains namespace-approved.
	for _, kind := range []struct{ group, version, kind, plural string }{{"cert-manager.io", "v1", "Issuer", "issuers"}, {"cert-manager.io", "v1", "Certificate", "certificates"}, {"gateway.envoyproxy.io", "v1alpha1", "EnvoyProxy", "envoyproxies"}, {"monitoring.coreos.com", "v1alpha1", "PrometheusAgent", "prometheusagents"}} {
		preserve := true
		env.CRDs = append(env.CRDs, &apiextv1.CustomResourceDefinition{
			ObjectMeta: metav1.ObjectMeta{Name: kind.plural + "." + kind.group},
			Spec: apiextv1.CustomResourceDefinitionSpec{Group: kind.group, Names: apiextv1.CustomResourceDefinitionNames{Plural: kind.plural, Kind: kind.kind}, Scope: apiextv1.NamespaceScoped,
				Versions: []apiextv1.CustomResourceDefinitionVersion{{Name: kind.version, Served: true, Storage: true, Schema: &apiextv1.CustomResourceValidation{OpenAPIV3Schema: &apiextv1.JSONSchemaProps{Type: "object", XPreserveUnknownFields: &preserve}}}}},
		})
	}
	env.ControlPlane.GetAPIServer().Configure().Set("authorization-mode", "RBAC")
	cfg, err := env.Start()
	require.NoError(t, err)
	t.Cleanup(func() { require.NoError(t, env.Stop()) })
	admin, err := kubernetes.NewForConfig(cfg)
	require.NoError(t, err)
	ctx := context.Background()
	for _, ns := range []string{"control", "sops-secrets", "envoy-gateway-system", "other-gateway"} {
		_, err = admin.CoreV1().Namespaces().Create(ctx, &corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: ns}}, metav1.CreateOptions{})
		require.NoError(t, err)
	}
	_, err = admin.CoreV1().ServiceAccounts("control").Create(ctx, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "reader"}}, metav1.CreateOptions{})
	require.NoError(t, err)
	_, err = admin.RbacV1().ClusterRoles().Create(ctx, role, metav1.CreateOptions{})
	require.NoError(t, err)
	_, err = admin.RbacV1().ClusterRoles().Create(ctx, extraRole, metav1.CreateOptions{})
	require.NoError(t, err)
	_, err = admin.RbacV1().ClusterRoleBindings().Create(ctx, &rbacv1.ClusterRoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "read"}, RoleRef: rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "ClusterRole", Name: role.Name}, Subjects: []rbacv1.Subject{{Kind: "ServiceAccount", Name: "reader", Namespace: "control"}}}, metav1.CreateOptions{})
	require.NoError(t, err)
	native := &rbacv1.Role{ObjectMeta: metav1.ObjectMeta{Name: "sops-age-keygen-privkey", Namespace: "sops-secrets"}, Rules: []rbacv1.PolicyRule{{APIGroups: []string{""}, Resources: []string{"secrets"}, Verbs: []string{"get"}, ResourceNames: []string{"sops-age-key"}}}}
	_, err = admin.RbacV1().Roles(native.Namespace).Create(ctx, native, metav1.CreateOptions{})
	require.NoError(t, err)
	_, err = admin.CoreV1().Secrets(native.Namespace).Create(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: "sops-age-key"}, Data: map[string][]byte{"key": []byte("test-only")}}, metav1.CreateOptions{})
	require.NoError(t, err)
	restricted := rest.CopyConfig(cfg)
	restricted.Impersonate = rest.ImpersonationConfig{UserName: "system:serviceaccount:control:reader", Groups: []string{"system:serviceaccounts", "system:serviceaccounts:control", "system:authenticated"}}
	reader, err := kubernetes.NewForConfig(restricted)
	require.NoError(t, err)
	require.Eventually(t, func() bool {
		_, err := reader.RbacV1().Roles(native.Namespace).Get(ctx, native.Name, metav1.GetOptions{})
		return err == nil
	}, 5*time.Second, 50*time.Millisecond)
	inventory, err := reader.RbacV1().Roles(native.Namespace).List(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	require.Len(t, inventory.Items, 1)
	watch, err := reader.RbacV1().Roles(native.Namespace).Watch(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	watch.Stop()
	_, err = reader.CoreV1().Secrets(native.Namespace).Get(ctx, "sops-age-key", metav1.GetOptions{})
	require.True(t, apierrors.IsForbidden(err), "Secret read must remain denied: %v", err)
	_, err = reader.CoreV1().Secrets(native.Namespace).List(ctx, metav1.ListOptions{})
	require.True(t, apierrors.IsForbidden(err), "Secret list must remain denied: %v", err)

	// Cluster-scoped RBAC definitions are readable without any namespace grant.
	_, err = reader.RbacV1().ClusterRoles().Get(ctx, role.Name, metav1.GetOptions{})
	require.NoError(t, err)
	_, err = reader.RbacV1().ClusterRoles().List(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	roleWatch, err := reader.RbacV1().ClusterRoles().Watch(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	roleWatch.Stop()
	_, err = reader.RbacV1().ClusterRoleBindings().Get(ctx, "read", metav1.GetOptions{})
	require.NoError(t, err)
	_, err = reader.RbacV1().ClusterRoleBindings().List(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	bindingWatch, err := reader.RbacV1().ClusterRoleBindings().Watch(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	bindingWatch.Stop()
	require.True(t, apierrors.IsForbidden(reader.RbacV1().ClusterRoles().Delete(ctx, role.Name, metav1.DeleteOptions{})))
	require.True(t, apierrors.IsForbidden(reader.RbacV1().ClusterRoleBindings().Delete(ctx, "read", metav1.DeleteOptions{})))

	adminDynamic, err := dynamic.NewForConfig(cfg)
	require.NoError(t, err)
	restrictedDynamic, err := dynamic.NewForConfig(restricted)
	require.NoError(t, err)
	_, err = admin.CoreV1().Secrets("envoy-gateway-system").Create(ctx, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: "gateway-tls"}, Type: corev1.SecretTypeTLS, Data: map[string][]byte{"tls.crt": []byte("test-only"), "tls.key": []byte("test-only")}}, metav1.CreateOptions{})
	require.NoError(t, err)
	for _, resource := range []struct {
		kind, plural string
		spec         map[string]interface{}
	}{
		{"Issuer", "issuers", map[string]interface{}{"selfSigned": map[string]interface{}{}}},
		{"Certificate", "certificates", map[string]interface{}{"secretName": "gateway-tls", "issuerRef": map[string]interface{}{"name": "gateway"}}},
	} {
		t.Run(resource.kind, func(t *testing.T) {
			gvr := schema.GroupVersionResource{Group: "cert-manager.io", Version: "v1", Resource: resource.plural}
			object := &unstructured.Unstructured{Object: map[string]interface{}{"apiVersion": "cert-manager.io/v1", "kind": resource.kind, "metadata": map[string]interface{}{"name": "gateway", "namespace": "envoy-gateway-system", "labels": map[string]interface{}{delivery.OwnerLabel: "gateway-owner"}}, "spec": resource.spec}}
			_, err := adminDynamic.Resource(gvr).Namespace("envoy-gateway-system").Create(ctx, object, metav1.CreateOptions{})
			require.NoError(t, err)
			scoped := restrictedDynamic.Resource(gvr).Namespace("envoy-gateway-system")
			_, err = scoped.Get(ctx, "gateway", metav1.GetOptions{})
			require.NoError(t, err, "restricted inventory GET needs no namespace grant")
			options := metav1.ListOptions{LabelSelector: delivery.OwnerLabel + "=gateway-owner"}
			owned, err := scoped.List(ctx, options)
			require.NoError(t, err)
			require.Len(t, owned.Items, 1, "cleanup must see retained native output")
			watcher, err := scoped.Watch(ctx, options)
			require.NoError(t, err)
			watcher.Stop()
			require.True(t, apierrors.IsForbidden(scoped.Delete(ctx, "gateway", metav1.DeleteOptions{})), "read policy must not grant writes")
			require.NoError(t, adminDynamic.Resource(gvr).Namespace("envoy-gateway-system").Delete(ctx, "gateway", metav1.DeleteOptions{}))
			owned, err = scoped.List(ctx, options)
			require.NoError(t, err)
			require.Empty(t, owned.Items, "cleanup can observe actual prune")
		})
	}
	_, err = reader.CoreV1().Secrets("envoy-gateway-system").Get(ctx, "gateway-tls", metav1.GetOptions{})
	require.True(t, apierrors.IsForbidden(err), "TLS private key must remain denied: %v", err)
	_, err = reader.CoreV1().Secrets("envoy-gateway-system").List(ctx, metav1.ListOptions{})
	require.True(t, apierrors.IsForbidden(err), "TLS Secret list must remain denied: %v", err)
	err = reader.RbacV1().Roles(native.Namespace).Delete(ctx, native.Name, metav1.DeleteOptions{})
	require.True(t, apierrors.IsForbidden(err), "Role writes must remain denied: %v", err)
	// Only the human-approved namespace binding opens EnvoyProxy and Secret
	// reads. The base role alone cannot read inline bootstrap credentials.
	envoyGVR := schema.GroupVersionResource{Group: "gateway.envoyproxy.io", Version: "v1alpha1", Resource: "envoyproxies"}
	for _, ns := range []string{"envoy-gateway-system", "other-gateway"} {
		object := &unstructured.Unstructured{Object: map[string]interface{}{"apiVersion": "gateway.envoyproxy.io/v1alpha1", "kind": "EnvoyProxy", "metadata": map[string]interface{}{"name": "gateway", "namespace": ns}, "spec": map[string]interface{}{"provider": map[string]interface{}{"type": "Kubernetes"}}}}
		_, err = adminDynamic.Resource(envoyGVR).Namespace(ns).Create(ctx, object, metav1.CreateOptions{})
		require.NoError(t, err)
	}
	envoyReader := restrictedDynamic.Resource(envoyGVR).Namespace("envoy-gateway-system")
	_, err = envoyReader.Get(ctx, "gateway", metav1.GetOptions{})
	require.True(t, apierrors.IsForbidden(err))
	_, err = envoyReader.List(ctx, metav1.ListOptions{})
	require.True(t, apierrors.IsForbidden(err))
	promGVR := schema.GroupVersionResource{Group: "monitoring.coreos.com", Version: "v1alpha1", Resource: "prometheusagents"}
	for _, ns := range []string{"envoy-gateway-system", "other-gateway"} {
		object := &unstructured.Unstructured{Object: map[string]interface{}{"apiVersion": "monitoring.coreos.com/v1alpha1", "kind": "PrometheusAgent", "metadata": map[string]interface{}{"name": "metrics", "namespace": ns}, "spec": map[string]interface{}{"remoteWrite": []interface{}{map[string]interface{}{"bearerToken": "synthetic-test-only"}}}}}
		_, err = adminDynamic.Resource(promGVR).Namespace(ns).Create(ctx, object, metav1.CreateOptions{})
		require.NoError(t, err)
	}
	promReader := restrictedDynamic.Resource(promGVR).Namespace("envoy-gateway-system")
	_, err = promReader.Get(ctx, "metrics", metav1.GetOptions{})
	require.True(t, apierrors.IsForbidden(err))
	_, err = promReader.List(ctx, metav1.ListOptions{})
	require.True(t, apierrors.IsForbidden(err))

	binding := &rbacv1.RoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "approved-read", Namespace: "envoy-gateway-system"}, RoleRef: rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "ClusterRole", Name: extraRole.Name}, Subjects: []rbacv1.Subject{{Kind: "ServiceAccount", Name: "reader", Namespace: "control"}}}
	_, err = admin.RbacV1().RoleBindings(binding.Namespace).Create(ctx, binding, metav1.CreateOptions{})
	require.NoError(t, err)
	require.Eventually(t, func() bool { _, err := envoyReader.Get(ctx, "gateway", metav1.GetOptions{}); return err == nil }, 5*time.Second, 50*time.Millisecond)
	_, err = promReader.Get(ctx, "metrics", metav1.GetOptions{})
	require.NoError(t, err)
	promObjects, err := promReader.List(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	require.Len(t, promObjects.Items, 1)
	promWatch, err := promReader.Watch(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	promWatch.Stop()
	_, err = restrictedDynamic.Resource(promGVR).Namespace("other-gateway").List(ctx, metav1.ListOptions{})
	require.True(t, apierrors.IsForbidden(err))
	require.True(t, apierrors.IsForbidden(promReader.Delete(ctx, "metrics", metav1.DeleteOptions{})))

	objects, err := envoyReader.List(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	require.Len(t, objects.Items, 1)
	watcher, err := envoyReader.Watch(ctx, metav1.ListOptions{})
	require.NoError(t, err)
	watcher.Stop()
	_, err = reader.CoreV1().Secrets(binding.Namespace).Get(ctx, "gateway-tls", metav1.GetOptions{})
	require.NoError(t, err, "read-extra approval explicitly includes Secrets in this namespace")
	_, err = restrictedDynamic.Resource(envoyGVR).Namespace("other-gateway").List(ctx, metav1.ListOptions{})
	require.True(t, apierrors.IsForbidden(err), "approval must not expose another namespace")
	_, err = reader.CoreV1().Secrets("sops-secrets").Get(ctx, "sops-age-key", metav1.GetOptions{})
	require.True(t, apierrors.IsForbidden(err), "approval must not expose another namespace's key")
	require.True(t, apierrors.IsForbidden(envoyReader.Delete(ctx, "gateway", metav1.DeleteOptions{})))
	require.NoError(t, admin.RbacV1().RoleBindings(binding.Namespace).Delete(ctx, binding.Name, metav1.DeleteOptions{}))
	require.Eventually(t, func() bool { _, err := envoyReader.List(ctx, metav1.ListOptions{}); return apierrors.IsForbidden(err) }, 5*time.Second, 50*time.Millisecond)
	require.Eventually(t, func() bool { _, err := promReader.List(ctx, metav1.ListOptions{}); return apierrors.IsForbidden(err) }, 5*time.Second, 50*time.Millisecond)

}
