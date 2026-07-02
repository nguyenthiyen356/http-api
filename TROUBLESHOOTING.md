# Troubleshooting Notes

This note compares the broken manifest with the fixed one and records the issues that had to be corrected. The important theme is that each problem was not just a syntax issue; each one blocked a real runtime behavior such as scheduling, health, traffic flow, or configuration mounting.

## 1. The default-deny policy blocked legitimate traffic

- Symptom: The workload could not be reached in a normal way because the network policy stopped the expected traffic before it ever reached the application.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot pod -l app=web`
  - `kubectl describe -n troubleshoot svc web-svc`
  - `kubectl get -n troubleshoot pods,svc,networkpolicies`
- Root cause: The manifest had a default-deny policy, but it did not allow the minimal ingress and egress paths that the smoke client, the web pods, and DNS needed. In other words, the policy was present, but it was too restrictive to support the workload’s expected communication.
- Fix: The fixed manifest added least-privilege allow rules. It permitted ingress from the smoke client on port 80, allowed egress from the web pods to the other web pods on port 80, and allowed DNS traffic to the kube-system DNS service on UDP and TCP port 53. That preserved the default-deny posture while restoring the connectivity the workload required.

## 2. The web container was pinned to an unusable image tag

- Symptom: The web pods failed to start because the image could not be pulled successfully.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot pod -l app=web`
  - `kubectl describe -n troubleshoot pod <web-pod-name>`
  - `kubectl get -n troubleshoot events --sort-by=.metadata.creationTimestamp`
- Root cause: The broken manifest referenced nginx:1.25.99. That tag was not a reliable choice for the environment, so the container image could not be resolved as expected.
- Fix: The fixed manifest switched to nginx:1.25.5, which restored the image pull path and allowed the container to start normally.

## 3. The web workload requested far more memory than the node could comfortably host

- Symptom: The web pods were not scheduled successfully because the requested memory was too high for the available node capacity.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot pod -l app=web`
  - `kubectl get -n troubleshoot pods -o wide`
  - `kubectl describe -n troubleshoot node`
- Root cause: The broken manifest set both the request and the limit for memory to 16Gi. That is a very large allocation for this scenario and was beyond what the node could support reliably. The problem was not that the container needed that much memory in principle; it was that the manifest asked for more than the environment could schedule.
- Fix: The fixed manifest reduced both the request and the limit to 2Gi. That kept the workload realistic while matching the capacity constraints of the cluster and allowing the pods to land on a node.

## 4. The health probes were checking the wrong port

- Symptom: The web pods were unhealthy because the liveness and readiness probes targeted a port that the container was not serving.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot pod -l app=web`
  - `kubectl get -n troubleshoot pods`
  - `kubectl describe -n troubleshoot svc web-svc`
- Root cause: The broken manifest used port 8080 for both probes, but the container exposed port 80. The probes were therefore checking a port that did not match the container’s actual listener.
- Fix: The fixed manifest aligned both probes with port 80 and also gave the container port a name so the service and probes could refer to a stable target. That made the health checks consistent with the running container.

## 5. The web pod could not mount the expected HTML content

- Symptom: The web container started without the intended content because its volume mount pointed at a ConfigMap that did not exist.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot pod -l app=web`
  - `kubectl describe -n troubleshoot pod <web-pod-name>`
  - `kubectl get -n troubleshoot events --sort-by=.metadata.creationTimestamp`
- Root cause: The volume definition referenced a ConfigMap named web-conf, but the actual ConfigMap created in the manifest was named web-config. The pod therefore had a broken mount reference.
- Fix: The fixed manifest changed the volume’s ConfigMap reference to web-config so the volume mounted correctly and the application could serve the expected HTML.

## 6. The Service was not targeting the right workload labels

- Symptom: The Service had no usable endpoints, so traffic could not be routed to the web pods even though the pods existed.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot svc web-svc`
  - `kubectl get -n troubleshoot endpoints web-svc`
  - `kubectl get -n troubleshoot pods -l app=web`
- Root cause: The Service selected app: webapp, but the Deployment labeled its pods with app: web. A selector mismatch meant the Service could not discover the pods it was supposed to front.
- Fix: The fixed manifest updated the Service selector to app: web and added matching labels to the Service itself. It also aligned the target port with the named container port so traffic reached the application correctly.

## 7. The AI workload was scheduled against the wrong node label and could not tolerate the GPU taint

- Symptom: The AI inference pod stayed unscheduled because it did not match the node label that the workload was intended to use and it could not bypass the taint that protected the GPU node.
- Commands used to diagnose it:
  - `kubectl describe -n troubleshoot pod -l app=ai-inference`
  - `kubectl get -n troubleshoot pods -o wide`
  - `kubectl describe -n troubleshoot node`
- Root cause: The broken manifest used nodeSelector with the key node-type: gpu, but the environment expected the label under the acme.io/ prefix. On top of that, the GPU node had a taint that prevented normal pods from landing there unless they explicitly tolerated it.
- Fix: The fixed manifest used the correct label key, acme.io/node-type: gpu, and added a toleration for the nvidia.com/gpu taint. That let the workload target the intended GPU-labeled node without changing the node itself.
